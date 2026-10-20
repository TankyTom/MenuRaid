import Foundation
import UserNotifications

nonisolated enum NotificationAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case allowed
}

/// Posts notifications. A protocol so tests can use a fake and never touch the real notification centre.
nonisolated protocol Notifying: Sendable {
    func authorizationStatus() async -> NotificationAuthorization
    /// Asks macOS for permission (shows the system prompt the first time). Returns whether it was granted.
    func requestAuthorization() async -> Bool
    func post(_ notification: ProblemNotification) async
    /// Starts handling clicks on notifications. `onOpen` is called when one is clicked.
    func activate(onOpen: @escaping @MainActor @Sendable () -> Void)
}

/// The real thing, using `UserNotifications`. Local notifications only: nothing is sent anywhere.
/// It touches `UNUserNotificationCenter` only when used, so merely creating one is harmless (and safe in tests).
nonisolated final class SystemNotifier: NSObject, Notifying, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var onOpen: (@MainActor @Sendable () -> Void)?

    private var center: UNUserNotificationCenter { .current() }

    func activate(onOpen: @escaping @MainActor @Sendable () -> Void) {
        lock.withLock { self.onOpen = onOpen }
        center.delegate = self
    }

    func authorizationStatus() async -> NotificationAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .allowed
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func post(_ notification: ProblemNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = "menuraid.problems"
        let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)
        try? await center.add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show the banner even while MenuRaid is the active app (its panel is open).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let handler = lock.withLock { onOpen }
        if let handler { await handler() }
    }
}
