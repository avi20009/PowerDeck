import Foundation
import UserNotifications

/// macOS notifications for plug-ins and warnings, used only when the user turns them on.
enum Notifier {
    /// The notification center needs an app bundle; the bare command-line binary has none.
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func post(_ event: ActivityEvent) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.detail
        let request = UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
