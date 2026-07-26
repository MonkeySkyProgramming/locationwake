import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    private static var hasRecordedForegroundLaunch = false

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: AlarmListSwiftUIView())
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {}

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard !AppRuntime.shouldSuppressExternalSideEffects else { return }
        LocationManager.shared.restoreSavedAlarms(reason: "sceneBecameActive")
        AlarmActivityCenter.shared.presentCurrentAlarmIfNeeded()
        ATTAuthorizationCoordinator.shared.requestIfEligible()
    }

    func sceneWillResignActive(_ scene: UIScene) {}

    func sceneWillEnterForeground(_ scene: UIScene) {
        guard !AppRuntime.shouldSuppressExternalSideEffects,
              !Self.hasRecordedForegroundLaunch else {
            return
        }
        Self.hasRecordedForegroundLaunch = true
        AppLaunchCounter.recordColdLaunch()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {}
}
