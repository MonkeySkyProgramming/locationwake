import Foundation
import CoreLocation
import UserNotifications
import AVFoundation
import UIKit

protocol LocationManagerDelegate: AnyObject {
    func didUpdateAlarmStatus(_ alarm: Alarm)
}

class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    weak var delegate: LocationManagerDelegate? // デリゲートプロパティ

    public var locationManager: CLLocationManager
    private var monitoringTimer: Timer?
    private var vibrationTimer: Timer?
    private var authorizationCheckTimer: Timer?

    var alarms: [Alarm] = [] // アラームリスト

    var skipNames: Set<String> = []

    private var soundPlayer = SoundPlayer.shared

    override init() {
        locationManager = CLLocationManager()
        super.init()
        // 必要な設定: バックグラウンド位置情報更新を有効化し、自動停止を無効化
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        let currentStatus = locationManager.authorizationStatus
        if currentStatus != .authorizedAlways {
            print("📣 位置情報の常に許可が必要です。リクエスト中...")
            locationManager.requestAlwaysAuthorization()
        } else {
            print("✅ locationManager.authorizationStatus により常に許可が検出されました")
        }
        locationManager.delegate = self
        // 認可ステータスの変化確認のために毎回チェック
        self.locationManagerDidChangeAuthorization(self.locationManager)
        locationManager.startUpdatingLocation()
        
        // iOSに「常に許可」ダイアログを促すため、ダミーのジオフェンスを追加
        if locationManager.authorizationStatus == .authorizedAlways {
            // Attempt to trigger background location update mechanism
            if let currentLocation = locationManager.location {
                let dummyRegion = CLCircularRegion(center: currentLocation.coordinate, radius: 50.0, identifier: "BackgroundTrigger")
                dummyRegion.notifyOnEntry = true
                dummyRegion.notifyOnExit = true
                locationManager.startMonitoring(for: dummyRegion)
                print("📣 仮ジオフェンスを追加して常に許可のダイアログを誘導")
            }
        }

        // 通知の許可をリクエスト
        NotificationManager.shared.requestNotificationPermission()

        // 監視領域を定期的に出力するためのタイマーを開始
        startMonitoringGeofenceStatus()
        // 追加: 定期的な認可ステータスチェックを開始
        startAuthorizationStatusCheck()

        // 初回起動後の1分後に位置情報の常に許可を促すアラートを表示
        DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) { [weak self] in
            self?.promptUserToEnableLocationSettings()
        }
    }

    // タイマーを使って監視領域を常に出力
    func startMonitoringGeofenceStatus() {
        monitoringTimer?.invalidate() // 既存のタイマーがあれば停止
        // 追加: 現在の許可ステータスを確認し、ユーザーに案内
        let currentStatus = CLLocationManager.authorizationStatus()
        if currentStatus != .authorizedAlways {
            print("⚠️ アプリの設定で『常に許可』に変更してください → 位置情報がバックグラウンドで必要です。")
        }
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.printGeodefence()
        }
    }

    // Geofenceの監視を開始する
    func startMonitoring(alarms: [Alarm], skipImmediateCheck: Bool = false) {
        self.alarms = alarms // アラームを保持
        if let currentLocation = locationManager.location?.coordinate, !skipImmediateCheck {
            for alarm in alarms {
                if UserDefaults.standard.bool(forKey: "SkipTrigger_\(alarm.name)") {
                    print("🚫 \(alarm.name) は保存直後のため startMonitoring でトリガーをスキップ")
                    UserDefaults.standard.set(false, forKey: "SkipTrigger_\(alarm.name)") // Reset flag
                    continue
                }
                guard let location = alarm.location, let radius = alarm.radius else { continue }
                if alarm.hasTriggered {
                    print("⏹️ トリガー済みアラームをスキップ: \(alarm.name)")
                    continue
                }
                let region = CLCircularRegion(
                    center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                    radius: min(radius, 1000.0),
                    identifier: alarm.name
                )
                if region.contains(currentLocation) {
                    print("🚨 現在地は \(alarm.name) のジオフェンス内 → 即時トリガー")
                    triggerAlarm(for: alarm)
                }
            }
        }
        print("受け取ったアラームリスト: \(alarms.map { $0.name })")
        print("現在の監視領域(開始前): \(locationManager.monitoredRegions.map { $0.identifier })")

        // 既存の監視領域をすべて停止
        for region in locationManager.monitoredRegions {
            // 追加: dummy region の削除
            if region.identifier == "BackgroundTrigger" {
                locationManager.stopMonitoring(for: region)
                print("🧹 仮ジオフェンスを削除しました")
            } else {
                locationManager.stopMonitoring(for: region)
                print("監視を停止しました: \(region.identifier)")
            }
        }

        // 全領域クリア後、新しい監視を追加
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.ensureMonitoringCleared { [weak self] isCleared in
                guard let self = self else { return }
                if isCleared {
                    print("すべての監視領域がクリアされました。")
                    self.addGeofences(for: alarms)
                } else {
                    print("監視領域がまだクリアされていません: \(self.locationManager.monitoredRegions.map { $0.identifier })")
                }
            }
        }
    }

    // 監視領域が完全にクリアされることを確認
    func ensureMonitoringCleared(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if self.locationManager.monitoredRegions.isEmpty {
                completion(true)
            } else {
                // 残っている監視を再クリア
                for region in self.locationManager.monitoredRegions {
                    self.locationManager.stopMonitoring(for: region)
                    print("追加で監視を停止しました: \(region.identifier)")
                }
                self.ensureMonitoringCleared(completion: completion)
            }
        }
    }

    // 新しいジオフェンスを追加
    func addGeofences(for alarms: [Alarm]) {
        for alarm in alarms {

            print("⚙️ addGeofence 対象: \(alarm.name), 緯度: \(alarm.location?.latitude ?? 0), 半径: \(alarm.radius ?? 0), 有効: \(alarm.isAlarmEnabled)")
            // すべてのアラームに対してジオフェンスを設定するため、isAlarmEnabled のチェックは削除
            guard let location = alarm.location, let radius = alarm.radius else {
                print("アラーム \(alarm.name) の位置情報または半径が無効です")
                print("⛔ スキップされたアラーム: \(alarm.name)")
                continue
            }
            // すでに監視中の場合はスキップ
            if self.locationManager.monitoredRegions.contains(where: { $0.identifier == alarm.name }) {
                print("すでに監視中の領域があります: \(alarm.name)")
                continue
            }
            
            // 監視対象の領域を作成
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                radius: min(radius, 1000.0), // 半径を1000m以下に制限
                identifier: alarm.name
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true // Exit通知も有効にする
            
            if CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) {
                self.locationManager.startMonitoring(for: region)
                print("監視を開始したアラーム: \(alarm.name)")
            } else {
                print("CLCircularRegionの監視がサポートされていません")
            }
        }
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
            if let alarm = findAlarm(for: circularRegion.identifier), alarm.isAlarmEnabled {
                let today = Calendar.current.component(.weekday, from: Date()) - 1 // Sunday = 0
                if let repeatDays = alarm.repeatWeekdays, !repeatDays.isEmpty, !repeatDays.contains(today) {
                    print("アラーム \(alarm.name) は本日(\(today))は繰り返し対象外のためスキップ")
                    return
                }
                // hasTriggeredUntilExit チェック
                if alarm.hasTriggeredUntilExit {
                    print("🚫 \(alarm.name) は hasTriggeredUntilExit = true のためスキップ")
                    return
                }
                triggerAlarm(for: alarm)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("Geofence領域から出ました: \(region.identifier)")
        
        // 対象のアラームを検索し、トリガー済みフラグをリセットする
        if let index = alarms.firstIndex(where: { $0.name == region.identifier }) {
            // アラームの再トリガー状態をリセット（再入室時に再度アラームを発火させるためのフラグ）
            alarms[index].hasTriggered = false
            alarms[index].hasTriggeredUntilExit = false
            saveAlarms()
            
            // 既存のジオフェンスがある場合に再登録する
            // これにより、ユーザーが領域外に出た後、再入室時に didEnterRegion イベントが発生するようになります
            LocationManager.shared.startMonitoring(alarms: alarms)
        }
    }

    // アラーム名で該当するアラームを検索する関数
    private func findAlarm(for identifier: String) -> Alarm? {
        return alarms.first { $0.name == identifier }
    }

    // アラームをトリガーする処理（サウンド名を使用）
    private func triggerAlarm(for alarm: Alarm) {
        if skipNames.contains(alarm.name) {
            print("🚫 \(alarm.name) は保存直後（メモリ）でトリガーをスキップ")
            skipNames.remove(alarm.name)
            return
        }
        let skipKey = "SkipTrigger_\(alarm.name)"
        if UserDefaults.standard.bool(forKey: skipKey) {
            print("🚫 \(alarm.name) は保存直後のためトリガーをスキップ（フラグによる）")
            UserDefaults.standard.set(false, forKey: skipKey) // Reset after skipping
            return
        }
        let skipTimestampKey = "SkipTriggerAt_\(alarm.name)"
        if let savedDate = UserDefaults.standard.object(forKey: skipTimestampKey) as? Date {
            let interval = Date().timeIntervalSince(savedDate)
            if interval < 10 {
                print("⏳ 保存から \(interval) 秒未満のため \(alarm.name) トリガーをスキップ")
                return
            } else {
                UserDefaults.standard.removeObject(forKey: skipTimestampKey)
            }
        }

        // アラームがトリガー禁止状態ならスキップ
        if alarm.hasTriggeredUntilExit {
            print("🚫 \(alarm.name) は hasTriggeredUntilExit = true のためトリガーしません")
            return
        }

        // 曜日チェックとアラーム有効状態を確認
        let today = Calendar.current.component(.weekday, from: Date()) - 1 // Sunday = 0
        if !alarm.isAlarmEnabled {
            print("🚫 \(alarm.name) は isAlarmEnabled が false のためトリガーしません")
            return
        }
        if let repeatDays = alarm.repeatWeekdays, !repeatDays.isEmpty {
            if !repeatDays.contains(today) {
                print("🚫 \(alarm.name) は本日(\(today))は繰り返し対象外のためトリガーしません")
                return
            }
        }

        // 通知を削除してから新規スケジュール
        NotificationManager.shared.removeNotification(identifier: alarm.name)
        NotificationManager.shared.scheduleNotification(
            withTitle: "アラーム",
            message: "\(alarm.name)に到達しました！",
            identifier: alarm.name
        )
        let soundName = alarm.sound
        
        if alarm.isSoundEnabled {
            soundPlayer.playSound(named: soundName)
        }
        if alarm.isVibrationEnabled {
            HapticManager.triggerRepeated(.impactMedium, count: Int.max, interval: 1.0)
        }

        // アラームが作動したので isAlarmEnabled をオフにする
        if let index = alarms.firstIndex(where: { $0.name == alarm.name }) {
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
        let encoder = JSONEncoder()
        do {
            let encoded = try encoder.encode(alarms)
            UserDefaults.standard.set(encoded, forKey: "SavedAlarms")
            print("アラームが正常に保存されました。")
        } catch {
            print("アラームの保存に失敗しました: \(error)")
        }
    }

    // アラームを削除したときの監視停止処理
    func stopMonitoringForAlarm(alarm: Alarm) {
        for region in locationManager.monitoredRegions {
            if region.identifier == alarm.name {
                locationManager.stopMonitoring(for: region)
                print("アラームの監視を停止しました: \(alarm.name)")
            }
        }
        print("監視解除後の領域: \(locationManager.monitoredRegions.map { $0.identifier })")
    }
    // ユーザーの現在位置を継続的に出力
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        print("📍 現在位置: 緯度 \(location.coordinate.latitude), 経度 \(location.coordinate.longitude)")
        // 位置更新時、すでに監視領域内であれば即時トリガー
        for alarm in alarms {
            print("🔎 チェック中: \(alarm.name) / hasTriggered: \(alarm.hasTriggered)")

            // チェック: アラームが無効ならスキップ
            if !alarm.isAlarmEnabled {
                print("🚫 \(alarm.name) は isAlarmEnabled が false のためスキップ")
                continue
            }

            // チェック: 繰り返し曜日に該当しない場合はスキップ
            let today = Calendar.current.component(.weekday, from: Date()) - 1
            if let repeatDays = alarm.repeatWeekdays, !repeatDays.isEmpty, !repeatDays.contains(today) {
                print("🚫 \(alarm.name) は本日(\(today)) は繰り返し対象外のためスキップ")
                continue
            }

            // 追加: hasTriggeredUntilExit チェック
            if alarm.hasTriggeredUntilExit {
                print("🚫 \(alarm.name) は hasTriggeredUntilExit = true のためスキップ")
                continue
            }

            guard let loc = alarm.location, let radius = alarm.radius else { continue }
            let userLoc = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            let alarmLoc = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
            let distance = userLoc.distance(from: alarmLoc)
            print("📏 \(alarm.name) までの距離: \(Int(distance)) m")
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
                radius: min(radius, 1000.0),
                identifier: alarm.name
            )
            let skipTimestampKey = "SkipTriggerAt_\(alarm.name)"
            if let savedDate = UserDefaults.standard.object(forKey: skipTimestampKey) as? Date {
                let interval = Date().timeIntervalSince(savedDate)
                if interval < 10 {
                    print("⏳ didUpdateLocation: 保存直後 \(interval) 秒 → トリガー抑制")
                    continue
                }
            }

            if region.contains(location.coordinate), !alarm.hasTriggered {
                // 保存直後スキップ条件（メモリ）
                if skipNames.contains(alarm.name) {
                    print("🚫 didUpdateLocation: \(alarm.name) はメモリ上でスキップ")
                    skipNames.remove(alarm.name)
                    continue
                }

                // 保存直後スキップ条件（UserDefaultsフラグ）
                let skipKey = "SkipTrigger_\(alarm.name)"
                if UserDefaults.standard.bool(forKey: skipKey) {
                    print("🚫 didUpdateLocation: \(alarm.name) は UserDefaults フラグでスキップ")
                    UserDefaults.standard.set(false, forKey: skipKey)
                    continue
                }

                // 保存直後スキップ条件（UserDefaultsタイムスタンプ）
                let skipTimestampKey = "SkipTriggerAt_\(alarm.name)"
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
        switch status {
        case .authorizedAlways:
            print("✅ locationManagerDidChangeAuthorization: 実際に「常に許可」が付与されました")
        case .authorizedWhenInUse:
            print("⚠️ locationManagerDidChangeAuthorization: 「使用中のみ許可」です → 「常に許可」が必要です。設定アプリで変更してください")
            if !UserDefaults.standard.bool(forKey: "DidPromptForAlwaysPermission") {
                UserDefaults.standard.set(true, forKey: "DidPromptForAlwaysPermission")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.promptUserToEnableLocationSettings()
                }
            }
            manager.requestAlwaysAuthorization()
        case .denied, .restricted:
            print("❌ locationManagerDidChangeAuthorization: 位置情報の使用が制限または拒否されています。設定アプリで確認してください")
            promptUserToEnableLocationSettings()
        case .notDetermined:
            print("⏳ locationManagerDidChangeAuthorization: 位置情報の許可がまだ決定されていません")
            promptUserToEnableLocationSettings()
        @unknown default:
            print("⚠️ locationManagerDidChangeAuthorization: 未知の認可ステータス")
        }
    }
    private func promptUserToEnableLocationSettings() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return
        }

        let alert = UIAlertController(
            title: "位置情報の許可が必要です",
            message: "このアプリでは常に位置情報へのアクセスが必要です。設定画面から「常に許可」に変更してください。",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "設定へ", style: .default, handler: { _ in
            if let appSettings = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(appSettings)
            }
        }))
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel, handler: nil))

        rootVC.present(alert, animated: true, completion: nil)
    }

    // 追加: 定期的に認可ステータスをチェックするメソッド
    func startAuthorizationStatusCheck() {
        authorizationCheckTimer?.invalidate() // 既存のタイマーを停止
        authorizationCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.checkAuthorizationStatus()
        }
    }

    private func checkAuthorizationStatus() {
        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedAlways:
            print("🟢 位置情報は常に許可されています")
        case .authorizedWhenInUse:
            print("🟡 使用中のみ許可 → 常に許可が必要です")
            promptUserToEnableLocationSettings()
        case .denied, .restricted:
            print("🔴 拒否・制限されています")
            promptUserToEnableLocationSettings()
        case .notDetermined:
            print("⏳ まだ未決定です")
            promptUserToEnableLocationSettings()
        @unknown default:
            print("⚠️ 未知の状態")
        }
    }
}

