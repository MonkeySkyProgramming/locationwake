import UIKit
import GoogleMobileAds   // Google Mobile Ads SDK をインポート
import UserNotifications

enum AppRuntime {
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    /// Simulator screenshots use the real UI while omitting ads, permission prompts,
    /// and location monitoring. Pass `--screenshot-mode` as a launch argument.
    static var isScreenshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--screenshot-mode")
    }

    static var isUnitTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var shouldForceOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains("--show-onboarding")
    }

    static var shouldResetUITestData: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-reset-data")
    }

    static var shouldSimulateActiveAlarm: Bool {
        ProcessInfo.processInfo.arguments.contains("--simulate-active-alarm")
            || ProcessInfo.processInfo.environment["SIMULATE_ACTIVE_ALARM"] == "1"
    }

    static var shouldSuppressExternalSideEffects: Bool {
        isUnitTesting || isUITesting || isScreenshotMode
    }

    static var shouldShowBannerAds: Bool {
        !isScreenshotMode && !isUITesting && !isUnitTesting
    }
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        if AppRuntime.isUITesting && AppRuntime.shouldResetUITestData {
            UserDefaults.standard.removeObject(forKey: AlarmStore.savedAlarmsKey)
            UserDefaults.standard.removeObject(
                forKey: AppLifecycleDefaultsKey.onboardingCompleted
            )
            UserDefaults.standard.removeObject(forKey: "ActiveAlarmID")
            UserDefaults.standard.removeObject(forKey: "ActiveAlarmName")
        }

        if !AppRuntime.shouldSuppressExternalSideEffects {
            AppLaunchCounter.recordColdLaunch()
            MobileAds.shared.start { _ in }

            LocationManager.shared.restoreSavedAlarms(reason: "launch")
        }
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = AppDesign.tintUIColor

        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // アラーム音は SoundPlayer が再生するため、フォアグラウンドでは
        // 通知の重複音を鳴らさず、バナーと通知センターへの表示だけを行う。
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            completionHandler()
            return
        }

        // 通知タップだけでは停止せず、現在鳴っているアラームの停止画面を前面に出す。
        AlarmActivityCenter.shared.presentCurrentAlarmIfNeeded()
        completionHandler()
    }

    func applicationWillResignActive(_ application: UIApplication) {}

    func applicationDidEnterBackground(_ application: UIApplication) {}

    func applicationWillEnterForeground(_ application: UIApplication) {}

    func applicationDidBecomeActive(_ application: UIApplication) {
        guard !AppRuntime.shouldSuppressExternalSideEffects else { return }
        LocationManager.shared.restoreSavedAlarms(reason: "becameActive")
        AlarmActivityCenter.shared.presentCurrentAlarmIfNeeded()
        ATTAuthorizationCoordinator.shared.requestIfEligible()
    }

    func applicationWillTerminate(_ application: UIApplication) {}
}
