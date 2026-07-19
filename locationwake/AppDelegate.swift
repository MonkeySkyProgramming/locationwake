import AppTrackingTransparency
import AdSupport
import UIKit
import CoreLocation
import GoogleMobileAds   // Google Mobile Ads SDK をインポート
import SwiftUI
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

        if !AppRuntime.shouldSuppressExternalSideEffects {
            MobileAds.shared.start { _ in }

            if #available(iOS 14, *) {
                ATTrackingManager.requestTrackingAuthorization { status in
                    print("ATT ステータス: \(status.rawValue)")
                }
            }

            LocationManager.shared.restoreSavedAlarms(reason: "launch")
        }
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemGroupedBackground
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
        appearance.shadowColor = .clear
        appearance.shadowImage = UIImage()

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor(red: 0.0, green: 0.54, blue: 0.60, alpha: 1.0)

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

        // 通知からアプリを開いた場合も、フォアグラウンド遷移を待たず確実に停止する。
        SoundPlayer.shared.stopSound()
        HapticManager.stop()
        UserDefaults.standard.set(true, forKey: "ShouldShowAlarmStoppedScreen")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .alarmStopRequested, object: nil)
        }
        completionHandler()
    }

    func applicationWillResignActive(_ application: UIApplication) {}

    func applicationDidEnterBackground(_ application: UIApplication) {}

    func applicationWillEnterForeground(_ application: UIApplication) {}

    func applicationDidBecomeActive(_ application: UIApplication) {
        guard !AppRuntime.shouldSuppressExternalSideEffects else { return }
        LocationManager.shared.restoreSavedAlarms(reason: "becameActive")
    }

    func applicationWillTerminate(_ application: UIApplication) {}
}
