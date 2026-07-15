import Foundation
import CoreLocation
import UserNotifications
import AVFoundation
import UIKit

protocol LocationManagerDelegate: AnyObject {
    func didUpdateAlarmStatus(_ alarm: Alarm)
}

enum AlarmTriggerBlockReason: Equatable {
    case disabled
    case weekdayMismatch
    case triggeredUntilExit
    case memorySkip
    case storedSkipFlag
    case savedTooRecently
}

enum AlarmProximityAction: Equatable {
    case none
    case trigger
    case resetAfterExit
}

struct AlarmTriggerPolicy {
    static let saveSkipInterval: TimeInterval = 10

    static func weekdayIndex(for date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: date) - 1
    }

    static func blockReason(
        for alarm: Alarm,
        weekday: Int,
        hasMemorySkip: Bool = false,
        hasStoredSkipFlag: Bool = false,
        savedAt: Date? = nil,
        now: Date = Date()
    ) -> AlarmTriggerBlockReason? {
        if hasMemorySkip {
            return .memorySkip
        }
        if hasStoredSkipFlag {
            return .storedSkipFlag
        }
        if let savedAt, now.timeIntervalSince(savedAt) < saveSkipInterval {
            return .savedTooRecently
        }
        if alarm.hasTriggeredUntilExit {
            return .triggeredUntilExit
        }
        if !alarm.isAlarmEnabled {
            return .disabled
        }
        if let repeatDays = alarm.repeatWeekdays, !repeatDays.isEmpty, !repeatDays.contains(weekday) {
            return .weekdayMismatch
        }
        return nil
    }

    static func proximityAction(
        for alarm: Alarm,
        distance: CLLocationDistance,
        radius: CLLocationDistance,
        weekday: Int
    ) -> AlarmProximityAction {
        if alarm.hasTriggeredUntilExit {
            return distance > radius ? .resetAfterExit : .none
        }
        guard !alarm.hasTriggered,
              blockReason(for: alarm, weekday: weekday) == nil,
              distance <= radius else {
            return .none
        }
        return .trigger
    }
}

class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    static let maximumMonitoredGeofences = 20
    weak var delegate: LocationManagerDelegate? // デリゲートプロパティ

    public var locationManager: CLLocationManager
    private var monitoringTimer: Timer?
    private var authorizationCheckTimer: Timer?
    private var hasRestoredSavedAlarms = false

    var alarms: [Alarm] = [] // アラームリスト

    var skipAlarmIDs: Set<String> = []

    private var soundPlayer = SoundPlayer.shared
    private let alarmScheduler = AlarmScheduler()

    var maximumGeofenceRadius: Double? {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            return nil
        }
        let maximumDistance = locationManager.maximumRegionMonitoringDistance
        guard maximumDistance > 0 else { return nil }
        return min(maximumDistance, Alarm.maximumGeofenceRadius)
    }

    func restoreSavedAlarms(reason: String) {
        alarms = AlarmStore.load()
        hasRestoredSavedAlarms = true
        print("ℹ️ event=alarmsRestored reason=\(reason) count=\(alarms.count)")
        updateContinuousLocationMonitoring(for: locationManager.authorizationStatus)
        startMonitoring(alarms: alarms)
    }

    override init() {
        locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self

        guard !AppRuntime.shouldSuppressExternalSideEffects else {
            return
        }

        // 移動中の到着判定に必要な精度を保ちつつ、省電力設定でバックグラウンド更新する。
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50
        locationManager.activityType = .otherNavigation
        let currentStatus = locationManager.authorizationStatus
        if currentStatus == .authorizedAlways {
            print("✅ locationManager.authorizationStatus により常に許可が検出されました")
        }
        // 認可ステータスの変化確認のために毎回チェック
        self.locationManagerDidChangeAuthorization(self.locationManager)

        // 通知の許可をリクエスト
        NotificationManager.shared.requestNotificationPermission()

        // 監視領域の定期ログはデバッグビルドだけで使用する。
#if DEBUG
        startMonitoringGeofenceStatus()
#endif
        // 追加: 定期的な認可ステータスチェックを開始
        startAuthorizationStatusCheck()

        // 初回起動後の1分後に状態をチェック（必要な場合のみポップを表示）
        DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) { [weak self] in
            self?.checkAuthorizationStatus()
        }
    }

    // タイマーを使って監視領域を常に出力
    func startMonitoringGeofenceStatus() {
        monitoringTimer?.invalidate() // 既存のタイマーがあれば停止
        // 追加: 現在の許可ステータスを確認し、ユーザーに案内
        let currentStatus = locationManager.authorizationStatus
        if currentStatus != .authorizedAlways {
            print("⚠️ アプリの設定で『常に許可』に変更してください → 位置情報がバックグラウンドで必要です。")
        }
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.printGeodefence()
        }
    }

    // 保存済みアラームと監視領域を同期する。変更のない領域は停止しない。
    func startMonitoring(alarms: [Alarm], skipImmediateCheck: Bool = false) {
        self.alarms = Alarm.normalizedForPersistence(alarms)
        updateContinuousLocationMonitoring(for: locationManager.authorizationStatus)
        if let currentLocation = locationManager.location, !skipImmediateCheck {
            for alarm in Self.geofenceEligibleAlarms(from: self.alarms) {
                if UserDefaults.standard.bool(forKey: "SkipTrigger_\(alarm.id)") {
                    print("🚫 \(alarm.name) は保存直後のため startMonitoring でトリガーをスキップ")
                    UserDefaults.standard.set(false, forKey: "SkipTrigger_\(alarm.id)") // Reset flag
                    continue
                }
                guard let location = alarm.location, let radius = alarm.geofenceRadius else { continue }
                guard Self.isUsableLocation(
                    currentLocation,
                    maximumHorizontalAccuracy: Self.maximumHorizontalAccuracy(for: radius)
                ) else {
                    print("ℹ️ event=immediateTriggerSkipped alarmID=\(alarm.id) reason=staleOrInaccurateLocation")
                    continue
                }
                if alarm.hasTriggered {
                    print("⏹️ トリガー済みアラームをスキップ: \(alarm.name)")
                    continue
                }
                let destination = CLLocation(latitude: location.latitude, longitude: location.longitude)
                let current = CLLocation(latitude: currentLocation.coordinate.latitude, longitude: currentLocation.coordinate.longitude)
                if current.distance(from: destination) <= radius {
                    print("🚨 現在地は \(alarm.name) のジオフェンス内 → 即時トリガー")
                    triggerAlarm(for: alarm)
                }
            }
        }
        synchronizeGeofences()
    }

    static func geofenceEligibleAlarms(from alarms: [Alarm]) -> [Alarm] {
        alarms.filter { alarm in
            alarm.isAlarmEnabled && alarm.location != nil && alarm.geofenceRadius != nil
        }
    }

    private func geofenceRegion(for alarm: Alarm) -> CLCircularRegion? {
        guard usesGeofence(for: alarm),
              let location = alarm.location,
              let radius = alarm.geofenceRadius else {
            return nil
        }

        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
            radius: radius,
            identifier: alarm.id
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        return region
    }

    private func usesGeofence(for alarm: Alarm) -> Bool {
        guard let radius = alarm.geofenceRadius, let maximumGeofenceRadius else {
            return false
        }
        return radius <= maximumGeofenceRadius
    }

    private func geofenceAlarms(from alarms: [Alarm]) -> [Alarm] {
        Self.geofenceEligibleAlarms(from: alarms).filter(usesGeofence)
    }

    private func synchronizeGeofences() {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            print("❌ event=monitoringUnavailable reason=CLCircularRegion is not supported")
            return
        }

        let desiredAlarms = geofenceAlarms(from: alarms)
        let desiredByID = Dictionary(uniqueKeysWithValues: desiredAlarms.map { ($0.id, $0) })
        let currentRegions = locationManager.monitoredRegions
        var unchangedIDs = Set<String>()
        var regionsToStop = [CLRegion]()

        for region in currentRegions {
            guard let alarm = desiredByID[region.identifier],
                  let expectedRegion = geofenceRegion(for: alarm),
                  sameConfiguration(region, expectedRegion) else {
                regionsToStop.append(region)
                continue
            }
            unchangedIDs.insert(alarm.id)
        }

        for region in regionsToStop {
            locationManager.stopMonitoring(for: region)
            print("ℹ️ event=monitoringStopped alarmID=\(region.identifier) reason=removedOrChanged")
        }

        let alarmsToStart = desiredAlarms.filter { !unchangedIDs.contains($0.id) }
        let remainingCapacity = max(0, Self.maximumMonitoredGeofences - (currentRegions.count - regionsToStop.count))
        let alarmsWithinCapacity = Array(alarmsToStart.prefix(remainingCapacity))
        let excludedAlarms = alarmsToStart.dropFirst(remainingCapacity)

        if !excludedAlarms.isEmpty {
            print("⚠️ event=monitoringLimitReached limit=\(Self.maximumMonitoredGeofences) excludedAlarmIDs=\(excludedAlarms.map(\.id))")
        }

        for alarm in alarmsWithinCapacity {
            guard let region = geofenceRegion(for: alarm) else { continue }
            locationManager.startMonitoring(for: region)
            print("ℹ️ event=monitoringStartRequested alarmID=\(alarm.id) name=\(alarm.name)")
        }
    }

    private func sameConfiguration(_ currentRegion: CLRegion, _ expectedRegion: CLCircularRegion) -> Bool {
        guard let currentRegion = currentRegion as? CLCircularRegion else { return false }
        return currentRegion.identifier == expectedRegion.identifier
            && abs(currentRegion.center.latitude - expectedRegion.center.latitude) < 0.000_001
            && abs(currentRegion.center.longitude - expectedRegion.center.longitude) < 0.000_001
            && abs(currentRegion.radius - expectedRegion.radius) < 0.5
            && currentRegion.notifyOnEntry == expectedRegion.notifyOnEntry
            && currentRegion.notifyOnExit == expectedRegion.notifyOnExit
    }

    // 監視中のジオフェンス領域を定期的に表示するメソッド
    func printGeodefence() {
        print("現在監視中の領域: \(self.locationManager.monitoredRegions.map { $0.identifier })")
    }

    // Geofence領域に入ったときの処理
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        if let circularRegion = region as? CLCircularRegion {
            print("Geofence領域に入りました: \(circularRegion.identifier)")
            // アラーム名に基づいてアラームを検索し、サウンドを再生
            if let alarm = findAlarm(for: circularRegion.identifier) {
                let today = AlarmTriggerPolicy.weekdayIndex(for: Date())
                if let reason = AlarmTriggerPolicy.blockReason(for: alarm, weekday: today) {
                    print("🚫 \(alarm.name) は \(reason) のためスキップ")
                    return
                }
                triggerAlarm(for: alarm)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("Geofence領域から出ました: \(region.identifier)")
        
        // 対象のアラームを検索し、トリガー済みフラグをリセットする
        if let index = alarms.firstIndex(where: { $0.id == region.identifier }) {
            // アラームの再トリガー状態をリセット（再入室時に再度アラームを発火させるためのフラグ）
            alarms[index].hasTriggered = false
            alarms[index].hasTriggeredUntilExit = false
            saveAlarms()
            
            // 既存のジオフェンスがある場合に再登録する
            // これにより、ユーザーが領域外に出た後、再入室時に didEnterRegion イベントが発生するようになります
            LocationManager.shared.startMonitoring(alarms: alarms)
        }
    }

    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        UserDefaults.standard.removeObject(forKey: "MonitoringFailure_\(region.identifier)")
        let name = findAlarm(for: region.identifier)?.name ?? "不明"
        print("✅ event=monitoringStarted alarmID=\(region.identifier) name=\(name)")
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        let alarmID = region?.identifier ?? "unknown"
        if alarmID != "unknown" {
            UserDefaults.standard.set(error.localizedDescription, forKey: "MonitoringFailure_\(alarmID)")
        }
        let name = findAlarm(for: alarmID)?.name ?? "不明"
        print("❌ event=monitoringFailed alarmID=\(alarmID) name=\(name) reason=\(error.localizedDescription)")
    }

    // ジオフェンスIDで該当するアラームを検索する関数
    private func findAlarm(for identifier: String) -> Alarm? {
        return alarms.first { $0.id == identifier }
    }

    // アラームをトリガーする処理（サウンド名を使用）
    private func triggerAlarm(for alarm: Alarm) {
        let skipKey = "SkipTrigger_\(alarm.id)"
        let skipTimestampKey = "SkipTriggerAt_\(alarm.id)"
        let savedDate = UserDefaults.standard.object(forKey: skipTimestampKey) as? Date
        let today = AlarmTriggerPolicy.weekdayIndex(for: Date())

        if let blockReason = AlarmTriggerPolicy.blockReason(
            for: alarm,
            weekday: today,
            hasMemorySkip: skipAlarmIDs.contains(alarm.id),
            hasStoredSkipFlag: UserDefaults.standard.bool(forKey: skipKey),
            savedAt: savedDate
        ) {
            switch blockReason {
            case .memorySkip:
                print("🚫 \(alarm.name) は保存直後（メモリ）でトリガーをスキップ")
                skipAlarmIDs.remove(alarm.id)
            case .storedSkipFlag:
                print("🚫 \(alarm.name) は保存直後のためトリガーをスキップ（フラグによる）")
                UserDefaults.standard.set(false, forKey: skipKey)
            case .savedTooRecently:
                if let savedDate {
                    let interval = Date().timeIntervalSince(savedDate)
                    print("⏳ 保存から \(interval) 秒未満のため \(alarm.name) トリガーをスキップ")
                }
            case .triggeredUntilExit:
                print("🚫 \(alarm.name) は hasTriggeredUntilExit = true のためトリガーしません")
            case .disabled:
                print("🚫 \(alarm.name) は isAlarmEnabled が false のためトリガーしません")
            case .weekdayMismatch:
                print("🚫 \(alarm.name) は本日(\(today))は繰り返し対象外のためトリガーしません")
            }
            return
        }

        if let savedDate {
            let interval = Date().timeIntervalSince(savedDate)
            if interval >= AlarmTriggerPolicy.saveSkipInterval {
                UserDefaults.standard.removeObject(forKey: skipTimestampKey)
            }
        }

        alarmScheduler.scheduleAlarm(alarm: alarm)
        let soundName = alarm.sound
        
        if alarm.isSoundEnabled {
            soundPlayer.playSound(named: soundName)
        }
        if alarm.isVibrationEnabled {
            HapticManager.triggerRepeated(.impactMedium, count: Int.max, interval: 1.0)
        }

        // アラームが作動したので isAlarmEnabled をオフにする
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            // 繰り返し曜日が未設定または空の場合のみ isAlarmEnabled をオフにする
            if alarms[index].repeatWeekdays?.isEmpty ?? true {
                alarms[index].isAlarmEnabled = false
            }
            alarms[index].hasTriggered = true  // トリガー済みフラグをセット
            alarms[index].hasTriggeredUntilExit = true // 領域から出るまでトリガー禁止
            saveAlarms() // アラーム設定を保存
            print("\(alarm.name) のアラームがトリガーされ、無効化されました。")
            delegate?.didUpdateAlarmStatus(alarms[index])
            NotificationCenter.default.post(name: Notification.Name("AlarmUpdated"), object: nil)
        }

        // トリガー後に監視領域を再設定
        startMonitoring(alarms: alarms, skipImmediateCheck: false)

        // 追加: 現在のアラーム設定一覧を出力
        print("📋 現在のアラーム設定一覧:")
        for a in alarms {
            print("🔔 \(a.name) | 有効: \(a.isAlarmEnabled) | トリガー済み: \(a.hasTriggered) | hasTriggeredUntilExit: \(a.hasTriggeredUntilExit) | 繰り返し曜日: \(a.repeatWeekdays ?? []) | サウンド: \(a.sound) | バイブ: \(a.isVibrationEnabled) | 座標: \(a.location?.latitude ?? 0), \(a.location?.longitude ?? 0) | 半径: \(a.radius ?? 0)")
        }
    }

    // アラームを保存するメソッド
    func saveAlarms() {
        alarms = Alarm.normalizedForPersistence(alarms)
        AlarmStore.save(alarms)
        print("アラームが正常に保存されました。")
    }

    // アラームを削除したときの監視停止処理
    func stopMonitoringForAlarm(alarm: Alarm) {
        for region in locationManager.monitoredRegions {
            if region.identifier == alarm.id {
                locationManager.stopMonitoring(for: region)
                print("アラームの監視を停止しました: \(alarm.name)")
            }
        }
        alarmScheduler.cancelAlarm(alarm: alarm)
        print("監視解除後の領域: \(locationManager.monitoredRegions.map { $0.identifier })")
    }
    // ユーザーの現在位置を継続的に出力
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        print("📍 現在位置: 緯度 \(location.coordinate.latitude), 経度 \(location.coordinate.longitude)")
        // 全方式のアラームを再評価し、領域内で対象曜日へ変わった場合や
        // ジオフェンスの退出イベントを失った場合にも状態を回復する。
        for alarm in alarms {
            print("🔎 チェック中: \(alarm.name) / hasTriggered: \(alarm.hasTriggered)")

            guard let destination = alarm.location,
                  let radius = alarm.geofenceRadius else { continue }
            guard Self.isUsableLocation(
                location,
                maximumHorizontalAccuracy: Self.maximumHorizontalAccuracy(for: radius)
            ) else {
                print("ℹ️ event=locationUpdateSkipped alarmID=\(alarm.id) reason=staleOrInaccurateLocation")
                continue
            }
            let current = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            let target = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
            let distance = current.distance(from: target)
            let today = AlarmTriggerPolicy.weekdayIndex(for: Date())

            switch AlarmTriggerPolicy.proximityAction(
                for: alarm,
                distance: distance,
                radius: radius,
                weekday: today
            ) {
            case .resetAfterExit:
                if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
                    alarms[index].hasTriggered = false
                    alarms[index].hasTriggeredUntilExit = false
                    saveAlarms()
                    print("ℹ️ event=alarmResetAfterExit alarmID=\(alarm.id)")
                }
            case .none:
                continue
            case .trigger:
                print("📏 \(alarm.name) までの距離: \(Int(distance)) m")
                // 保存直後スキップ条件（メモリ）
                if skipAlarmIDs.contains(alarm.id) {
                    print("🚫 didUpdateLocation: \(alarm.name) はメモリ上でスキップ")
                    skipAlarmIDs.remove(alarm.id)
                    continue
                }

                // 保存直後スキップ条件（UserDefaultsフラグ）
                let skipKey = "SkipTrigger_\(alarm.id)"
                if UserDefaults.standard.bool(forKey: skipKey) {
                    print("🚫 didUpdateLocation: \(alarm.name) は UserDefaults フラグでスキップ")
                    UserDefaults.standard.set(false, forKey: skipKey)
                    continue
                }

                // 保存直後スキップ条件（UserDefaultsタイムスタンプ）
                let skipTimestampKey = "SkipTriggerAt_\(alarm.id)"
                if let savedDate = UserDefaults.standard.object(forKey: skipTimestampKey) as? Date {
                    let interval = Date().timeIntervalSince(savedDate)
                    if interval < 10 {
                        print("⏳ didUpdateLocation: 保存直後 \(interval) 秒 → トリガー抑制")
                        continue
                    }
                }

                print("🚨 didUpdateLocation中に \(alarm.name) に既に入っていた → 即時トリガー")
                triggerAlarm(for: alarm)
            }
        }
    }

    // iOS 14+ 向けの新しい認可変更コールバック
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        NotificationCenter.default.post(
            name: .locationAuthorizationDidChange,
            object: nil,
            userInfo: ["status": status.rawValue]
        )
        switch status {
        case .authorizedAlways:
            print("✅ locationManagerDidChangeAuthorization: 実際に「常に許可」が付与されました")
            updateContinuousLocationMonitoring(for: status)
            if hasRestoredSavedAlarms {
                startMonitoring(alarms: alarms)
            }
        case .authorizedWhenInUse:
            updateContinuousLocationMonitoring(for: status)
            print("⚠️ locationManagerDidChangeAuthorization: 「使用中のみ許可」です → 「常に許可」が必要です。設定アプリで変更してください")
        case .denied, .restricted:
            updateContinuousLocationMonitoring(for: status)
            print("❌ locationManagerDidChangeAuthorization: 位置情報の使用が制限または拒否されています。設定アプリで確認してください")
        case .notDetermined:
            updateContinuousLocationMonitoring(for: status)
            print("⏳ locationManagerDidChangeAuthorization: 位置情報の許可がまだ決定されていません")
        @unknown default:
            print("⚠️ locationManagerDidChangeAuthorization: 未知の認可ステータス")
        }
    }

    static func shouldRunContinuousLocationMonitoring(
        for status: CLAuthorizationStatus,
        alarms: [Alarm],
        maximumGeofenceRadius: CLLocationDistance?
    ) -> Bool {
        guard status == .authorizedAlways else { return false }
        return geofenceEligibleAlarms(from: alarms).contains { alarm in
            let usesSelectedWeekdays = !(alarm.repeatWeekdays?.isEmpty ?? true)
            guard let maximumGeofenceRadius, let radius = alarm.geofenceRadius else {
                return true
            }
            return usesSelectedWeekdays || radius > maximumGeofenceRadius
        }
    }

    static func maximumHorizontalAccuracy(for radius: CLLocationDistance) -> CLLocationAccuracy {
        min(max(radius / 2, 100), 1_000)
    }

    static func isUsableLocation(
        _ location: CLLocation,
        now: Date = Date(),
        maximumAge: TimeInterval = 30,
        maximumHorizontalAccuracy: CLLocationAccuracy
    ) -> Bool {
        location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= maximumHorizontalAccuracy
            && abs(now.timeIntervalSince(location.timestamp)) <= maximumAge
    }

    private func updateContinuousLocationMonitoring(for status: CLAuthorizationStatus) {
        if Self.shouldRunContinuousLocationMonitoring(
            for: status,
            alarms: alarms,
            maximumGeofenceRadius: maximumGeofenceRadius
        ) {
            locationManager.startUpdatingLocation()
        } else {
            locationManager.stopUpdatingLocation()
        }
    }
    // 追加: 定期的に認可ステータスをチェックするメソッド
    func startAuthorizationStatusCheck() {
        authorizationCheckTimer?.invalidate() // 既存のタイマーを停止
        authorizationCheckTimer = Timer.scheduledTimer(withTimeInterval: 60.0 * 60.0, repeats: true) { [weak self] _ in
            let ts = String(format: "%.3f", Date().timeIntervalSince1970)
            print("⏱️ [AuthCheckTimer] fired at \(ts)")
            self?.checkAuthorizationStatus()
        }
    }

    private func checkAuthorizationStatus() {
        print("🔎 [AuthCheck] checking authorization... \(Date())")
        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedAlways:
            print("🟢 位置情報は常に許可されています")
        case .authorizedWhenInUse:
            print("🟡 使用中のみ許可 → 常に許可が必要です")
        case .denied, .restricted:
            print("🔴 拒否・制限されています")
        case .notDetermined:
            print("⏳ まだ未決定です")
        @unknown default:
            print("⚠️ 未知の状態")
        }
    }
}

extension Notification.Name {
    static let locationAuthorizationDidChange = Notification.Name("LocationAuthorizationDidChange")
}
