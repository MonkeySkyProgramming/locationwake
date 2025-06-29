import UIKit
import CoreLocation
import GoogleMobileAds   // Google Mobile Ads SDK をインポート
import SwiftUI

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var locationManager: CLLocationManager?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        locationManager = CLLocationManager()
        locationManager?.requestAlwaysAuthorization()
        
        MobileAds.shared.start { _ in }
        
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
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            let rootView = AlarmListSwiftUIView()
            let hostingController = UIHostingController(rootView: rootView)
            hostingController.view.tintColor = UIColor(named: "NavBarTintColor")
            window.rootViewController = hostingController
            self.window = window
            window.makeKeyAndVisible()
        }
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {}

    func applicationDidEnterBackground(_ application: UIApplication) {}

    func applicationWillEnterForeground(_ application: UIApplication) {}

    func applicationDidBecomeActive(_ application: UIApplication) {}

    func applicationWillTerminate(_ application: UIApplication) {}
}
