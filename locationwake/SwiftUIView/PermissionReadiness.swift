import Combine
import CoreLocation
import UIKit
import UserNotifications

enum PermissionReadinessIssue: String, CaseIterable, Identifiable {
    case locationAlways
    case preciseLocation
    case notificationAuthorization
    case notificationSound

    var id: String { rawValue }

    var title: String {
        switch self {
        case .locationAlways:
            return "位置情報を「常に許可」にしてください"
        case .preciseLocation:
            return "正確な位置情報をオンにしてください"
        case .notificationAuthorization:
            return "通知を許可してください"
        case .notificationSound:
            return "通知のサウンドをオンにしてください"
        }
    }

    var systemImage: String {
        switch self {
        case .locationAlways:
            return "location.slash.fill"
        case .preciseLocation:
            return "scope"
        case .notificationAuthorization:
            return "bell.slash.fill"
        case .notificationSound:
            return "speaker.slash.fill"
        }
    }
}

struct PermissionReadinessSnapshot: Equatable {
    let locationAuthorization: CLAuthorizationStatus
    let locationAccuracyAuthorization: CLAccuracyAuthorization
    let notificationAuthorization: UNAuthorizationStatus
    let notificationSoundSetting: UNNotificationSetting
    let backgroundRefreshStatus: UIBackgroundRefreshStatus
    let hasLoadedNotificationSettings: Bool

    var hasAlwaysLocationAuthorization: Bool {
        locationAuthorization == .authorizedAlways
    }

    var hasPreciseLocationAuthorization: Bool {
        locationAccuracyAuthorization == .fullAccuracy
    }

    var hasNotificationAuthorization: Bool {
        switch notificationAuthorization {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    var hasNotificationSound: Bool {
        notificationSoundSetting == .enabled
    }

    var hasBackgroundRefresh: Bool {
        backgroundRefreshStatus == .available
    }

    /// 保存済みアラームの信頼性ポップアップで扱う、最重要の2設定。
    var authorizationIssues: [PermissionReadinessIssue] {
        var result: [PermissionReadinessIssue] = []
        if !hasAlwaysLocationAuthorization {
            result.append(.locationAlways)
        }
        if hasLoadedNotificationSettings && !hasNotificationAuthorization {
            result.append(.notificationAuthorization)
        }
        return result
    }

    /// 設定画面で個別に回復方法を表示する、現在の不足項目。
    var issues: [PermissionReadinessIssue] {
        var result: [PermissionReadinessIssue] = []
        if !hasAlwaysLocationAuthorization {
            result.append(.locationAlways)
        }
        let canEvaluateAccuracy = locationAuthorization == .authorizedAlways
            || locationAuthorization == .authorizedWhenInUse
        if canEvaluateAccuracy && !hasPreciseLocationAuthorization {
            result.append(.preciseLocation)
        }
        if hasLoadedNotificationSettings && !hasNotificationAuthorization {
            result.append(.notificationAuthorization)
        }
        if hasLoadedNotificationSettings
            && hasNotificationAuthorization
            && !hasNotificationSound {
            result.append(.notificationSound)
        }
        return result
    }

    var isReadyForReliableArrival: Bool {
        // 「使用中のみ」はジオフェンスのバックグラウンド監視に十分ではないため、
        // 不足項目の表示内容とは独立して「常に許可」を完了条件として固定する。
        hasLoadedNotificationSettings
            && hasAlwaysLocationAuthorization
            && hasPreciseLocationAuthorization
            && hasNotificationAuthorization
            && hasNotificationSound
    }
}

final class PermissionReadiness: NSObject, ObservableObject {
    static let shared = PermissionReadiness()

    @Published private(set) var snapshot: PermissionReadinessSnapshot

    private let locationManager: CLLocationManager
    private let notificationCenter: UNUserNotificationCenter
    private let defaults: UserDefaults
    private var refreshGeneration = 0
    private var pendingRefreshCompletions: [() -> Void] = []

    private enum DefaultsKey {
        static let hasRequestedAlwaysUpgrade = "hasRequestedAlwaysLocationUpgrade"
    }

    init(
        locationManager: CLLocationManager = LocationManager.shared.locationManager,
        notificationCenter: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.locationManager = locationManager
        self.notificationCenter = notificationCenter
        self.defaults = defaults
        snapshot = PermissionReadinessSnapshot(
            locationAuthorization: locationManager.authorizationStatus,
            locationAccuracyAuthorization: locationManager.accuracyAuthorization,
            notificationAuthorization: .notDetermined,
            notificationSoundSetting: .notSupported,
            backgroundRefreshStatus: UIApplication.shared.backgroundRefreshStatus,
            hasLoadedNotificationSettings: false
        )
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAuthorizationEnvironmentChange),
            name: .locationAuthorizationDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAuthorizationEnvironmentChange),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func refresh(completion: (() -> Void)? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.refresh(completion: completion)
            }
            return
        }

        snapshot = makeSnapshot(
            notificationAuthorization: snapshot.notificationAuthorization,
            notificationSoundSetting: snapshot.notificationSoundSetting,
            hasLoadedNotificationSettings: snapshot.hasLoadedNotificationSettings
        )
        if let completion {
            pendingRefreshCompletions.append(completion)
        }
        refreshGeneration += 1
        let generation = refreshGeneration

        notificationCenter.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }
                guard generation == self.refreshGeneration else { return }
                self.snapshot = self.makeSnapshot(
                    notificationAuthorization: settings.authorizationStatus,
                    notificationSoundSetting: settings.soundSetting,
                    hasLoadedNotificationSettings: true
                )
                let completions = self.pendingRefreshCompletions
                self.pendingRefreshCompletions.removeAll()
                completions.forEach { $0() }
            }
        }
    }

    var canRequestAlwaysUpgradeInApp: Bool {
        snapshot.locationAuthorization == .authorizedWhenInUse
            && !defaults.bool(forKey: DefaultsKey.hasRequestedAlwaysUpgrade)
    }

    /// 必ず、位置情報が必要な理由を表示した後のユーザー操作から呼び出す。
    /// 初回は iOS の段階的な許可フローに従い、まず「使用中のみ」を求める。
    /// その許可後に同じ操作から「常に許可」へアップグレードする。
    func requestAlwaysLocationAuthorization() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            guard !defaults.bool(forKey: DefaultsKey.hasRequestedAlwaysUpgrade) else {
                openAppSettings()
                return
            }
            defaults.set(true, forKey: DefaultsKey.hasRequestedAlwaysUpgrade)
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways, .denied, .restricted:
            refresh()
        @unknown default:
            refresh()
        }
    }

    /// 必ず、通知が必要な理由を表示した後のユーザー操作から呼び出す。
    func requestNotificationAuthorization(completion: (() -> Void)? = nil) {
        NotificationManager.shared.requestNotificationPermission { [weak self] _ in
            self?.refresh(completion: completion)
        }
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @objc private func handleAuthorizationEnvironmentChange() {
        refresh()
    }

    private func makeSnapshot(
        notificationAuthorization: UNAuthorizationStatus,
        notificationSoundSetting: UNNotificationSetting,
        hasLoadedNotificationSettings: Bool
    ) -> PermissionReadinessSnapshot {
        PermissionReadinessSnapshot(
            locationAuthorization: locationManager.authorizationStatus,
            locationAccuracyAuthorization: locationManager.accuracyAuthorization,
            notificationAuthorization: notificationAuthorization,
            notificationSoundSetting: notificationSoundSetting,
            backgroundRefreshStatus: UIApplication.shared.backgroundRefreshStatus,
            hasLoadedNotificationSettings: hasLoadedNotificationSettings
        )
    }
}
