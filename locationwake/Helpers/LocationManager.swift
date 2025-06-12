import Foundation
import CoreLocation
import UserNotifications
import AVFoundation

protocol LocationManagerDelegate: AnyObject {
    func didUpdateAlarmStatus(_ alarm: Alarm)
}

class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    weak var delegate: LocationManagerDelegate? // デリゲートプロパティ

    private var locationManager: CLLocationManager
    private var monitoringTimer: Timer?

    var alarms: [Alarm] = [] // アラームリスト

    private var soundPlayer = SoundPlayer.shared

    override init() {
        locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()

        // 通知の許可をリクエスト
        NotificationManager.shared.requestNotificationPermission()

        // 監視領域を定期的に出力するためのタイマーを開始
        startMonitoringGeofenceStatus()
    }

    // タイマーを使って監視領域を常に出力
    func startMonitoringGeofenceStatus() {
        monitoringTimer?.invalidate() // 既存のタイマーがあれば停止
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.printGeodefence()
        }
    }

    // Geofenceの監視を開始する
    func startMonitoring(alarms: [Alarm]) {
        self.alarms = alarms // アラームを保持
        print("受け取ったアラームリスト: \(alarms.map { $0.name })")
        print("現在の監視領域(開始前): \(locationManager.monitoredRegions.map { $0.identifier })")

        // 既存の監視領域をすべて停止
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
            print("監視を停止しました: \(region.identifier)")
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
            // すべてのアラームに対してジオフェンスを設定するため、isAlarmEnabled のチェックは削除
            guard let location = alarm.location, let radius = alarm.radius else {
                print("アラーム \(alarm.name) の位置情報または半径が無効です")
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
            
            // 変更を保存する場合は、UserDefaults に保存
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

        // アラームが作動したので isAlarmEnabled をオフにする
        if let index = alarms.firstIndex(where: { $0.name == alarm.name }) {
            alarms[index].isAlarmEnabled = false
            alarms[index].hasTriggered = true  // トリガー済みフラグをセット
            saveAlarms() // アラーム設定を保存
            print("\(alarm.name) のアラームがトリガーされ、無効化されました。")
            delegate?.didUpdateAlarmStatus(alarms[index])
        }

        // トリガー後に監視領域を再設定
        startMonitoring(alarms: alarms)
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
}
