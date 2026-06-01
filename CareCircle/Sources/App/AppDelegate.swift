import UIKit

// MARK: - AppDelegate

/// Hosts the `CircleSceneDelegate` so SwiftUI scenes can receive
/// `windowScene(_:userDidAcceptCloudKitShareWith:)` callbacks, and bridges the
/// APNs device-token callbacks (which only land on the app delegate) to the
/// SwiftUI-owned `PushRegistrationService`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set by `CareCircleApp` once the SwiftUI environment is wired. The OS can
    /// deliver a device token before that happens, so a token that arrives
    /// early is buffered and flushed the instant the handler is installed.
    var pushTokenHandler: ((Data) -> Void)? {
        didSet {
            guard let token = bufferedDeviceToken else { return }
            bufferedDeviceToken = nil
            pushTokenHandler?(token)
        }
    }

    var pushFailureHandler: ((Error) -> Void)?

    private var bufferedDeviceToken: Data?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    )
        -> Bool
    {
        configureNavigationBarAppearance()
        return true
    }

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        if let handler = pushTokenHandler {
            handler(deviceToken)
        } else {
            bufferedDeviceToken = deviceToken
        }
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        pushFailureHandler?(error)
    }

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

    /// Paints both inline and large nav-bar titles in the brand forest green
    /// so they contrast against the cream background. SwiftUI's
    /// `.toolbarBackground` only handles the bar fill; title text color must
    /// be set through `UINavigationBarAppearance`.
    private func configureNavigationBarAppearance() {
        let titleColor = UIColor(
            red: 0.176,
            green: 0.416,
            blue: 0.310,
            alpha: 1.0
        )
        let background = UIColor(
            red: 0.969,
            green: 0.957,
            blue: 0.929,
            alpha: 1.0
        )

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = background
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: titleColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: titleColor]

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactAppearance = appearance
        bar.tintColor = titleColor
    }
}
