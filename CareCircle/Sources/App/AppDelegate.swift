import UIKit

// MARK: - AppDelegate

/// Hosts the `CircleSceneDelegate` so SwiftUI scenes can receive
/// `windowScene(_:userDidAcceptCloudKitShareWith:)` callbacks.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions
    )
        -> UISceneConfiguration
    {
        let configuration = UISceneConfiguration(
            name: "Default",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = CircleSceneDelegate.self
        return configuration
    }
}
