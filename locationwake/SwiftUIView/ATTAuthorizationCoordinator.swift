import AppTrackingTransparency
import Combine
import Foundation
import UIKit

enum AppLifecycleDefaultsKey {
    static let onboardingCompleted = "hasSeenOnboarding"
    static let coldLaunchCount = "appColdLaunchCount"
    static let hasRequestedTrackingAuthorization = "hasRequestedTrackingAuthorization"
}

enum AppLaunchCounter {
    @discardableResult
    static func recordColdLaunch(in defaults: UserDefaults = .standard) -> Int {
        let nextCount = max(0, defaults.integer(forKey: AppLifecycleDefaultsKey.coldLaunchCount)) + 1
        defaults.set(nextCount, forKey: AppLifecycleDefaultsKey.coldLaunchCount)
        return nextCount
    }

    static func coldLaunchCount(in defaults: UserDefaults = .standard) -> Int {
        max(0, defaults.integer(forKey: AppLifecycleDefaultsKey.coldLaunchCount))
    }
}

struct ATTRequestEligibility {
    static let minimumColdLaunchCount = 3

    static func shouldRequest(
        authorizationStatus: ATTrackingManager.AuthorizationStatus,
        coldLaunchCount: Int,
        savedAlarmCount: Int,
        hasCompletedOnboarding: Bool,
        hasRequestedTrackingAuthorization: Bool
    ) -> Bool {
        authorizationStatus == .notDetermined
            && coldLaunchCount >= minimumColdLaunchCount
            && savedAlarmCount > 0
            && hasCompletedOnboarding
            && !hasRequestedTrackingAuthorization
    }
}

final class ATTAuthorizationCoordinator: ObservableObject {
    static let shared = ATTAuthorizationCoordinator()

    @Published private(set) var authorizationStatus: ATTrackingManager.AuthorizationStatus

    private var hasRequestedThisSession = false

    private init() {
        authorizationStatus = ATTrackingManager.trackingAuthorizationStatus
    }

    /// アプリがアクティブで、オンボーディングやアラーム保存が完了した後に呼び出す。
    /// 条件を満たさない呼び出しは副作用を持たないため、active・保存完了の両方から再評価できる。
    @discardableResult
    func requestIfEligible(
        defaults: UserDefaults = .standard,
        savedAlarmCount: Int? = nil,
        authorizationStatus: ATTrackingManager.AuthorizationStatus? = nil
    ) -> Bool {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                _ = self?.requestIfEligible(
                    defaults: defaults,
                    savedAlarmCount: savedAlarmCount,
                    authorizationStatus: authorizationStatus
                )
            }
            return false
        }
        guard !AppRuntime.shouldSuppressExternalSideEffects,
              UIApplication.shared.applicationState == .active,
              !hasRequestedThisSession else {
            return false
        }

        let status = authorizationStatus ?? ATTrackingManager.trackingAuthorizationStatus
        let previousStatus = self.authorizationStatus
        if previousStatus != status {
            self.authorizationStatus = status
        }
        if status != .notDetermined {
            defaults.set(
                true,
                forKey: AppLifecycleDefaultsKey.hasRequestedTrackingAuthorization
            )
            if previousStatus == .notDetermined {
                NotificationCenter.default.post(
                    name: .trackingAuthorizationDidResolve,
                    object: status
                )
            }
            return false
        }
        let alarmCount = savedAlarmCount ?? AlarmStore.load(from: defaults).count
        let isEligible = ATTRequestEligibility.shouldRequest(
            authorizationStatus: status,
            coldLaunchCount: AppLaunchCounter.coldLaunchCount(in: defaults),
            savedAlarmCount: alarmCount,
            hasCompletedOnboarding: defaults.bool(
                forKey: AppLifecycleDefaultsKey.onboardingCompleted
            ),
            hasRequestedTrackingAuthorization: defaults.bool(
                forKey: AppLifecycleDefaultsKey.hasRequestedTrackingAuthorization
            )
        )
        guard isEligible else { return false }

        hasRequestedThisSession = true
        ATTrackingManager.requestTrackingAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authorizationStatus = status
                if status == .notDetermined {
                    self.hasRequestedThisSession = false
                } else {
                    defaults.set(
                        true,
                        forKey: AppLifecycleDefaultsKey.hasRequestedTrackingAuthorization
                    )
                    NotificationCenter.default.post(
                        name: .trackingAuthorizationDidResolve,
                        object: status
                    )
                }
#if DEBUG
                print("ATT ステータス: \(status.rawValue)")
#endif
            }
        }
        return true
    }
}

extension Notification.Name {
    static let trackingAuthorizationDidResolve = Notification.Name(
        "TrackingAuthorizationDidResolve"
    )
}
