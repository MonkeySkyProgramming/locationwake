import AppTrackingTransparency
import AdSupport
import UIKit
import CoreLocation
import GoogleMobileAds   // Google Mobile Ads SDK をインポート
import SwiftUI

enum AppRuntime {
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    static var isUnitTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var shouldSuppressExternalSideEffects: Bool {
        isUnitTesting || isUITesting
    }
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if !AppRuntime.shouldSuppressExternalSideEffects {
            MobileAds.shared.start { _ in }

            if #available(iOS 14, *) {
                ATTrackingManager.requestTrackingAuthorization { status in
                    print("ATT ステータス: \(status.rawValue)")
                }
            }
        }
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "NavBarColor")
        appearance.titleTextAttributes = [.foregroundColor: UIColor(named: "NavBarTintColor") ?? UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(named: "NavBarTintColor") ?? UIColor.white]
        appearance.buttonAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(named: "NavBarTintColor") ?? UIColor.white]
        appearance.backButtonAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(named: "NavBarTintColor") ?? UIColor.white]
        
        if let backImage = UIImage(systemName: "chevron.backward")?.withTintColor(UIColor(named: "NavBarTintColor") ?? .white, renderingMode: .alwaysOriginal) {
            appearance.setBackIndicatorImage(backImage, transitionMaskImage: backImage)
        }
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor(named: "NavBarTintColor")

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {}

    func applicationDidEnterBackground(_ application: UIApplication) {}

    func applicationWillEnterForeground(_ application: UIApplication) {}

    func applicationDidBecomeActive(_ application: UIApplication) {}

    func applicationWillTerminate(_ application: UIApplication) {}
}
