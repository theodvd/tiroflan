import Foundation
import UserNotifications

/// Notifications système : RDV qui commence, absence pendant le chrono, chrono oublié.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let eventCategory = "EVENT_START"
    static let idleCategory = "IDLE"
    static let longRunCategory = "LONG_RUN"

    weak var store: Store?

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let start = UNNotificationAction(identifier: "START", title: "Lancer le chrono", options: [])
        let remove = UNNotificationAction(identifier: "REMOVE_IDLE", title: "Retirer ce temps", options: [])
        let keep = UNNotificationAction(identifier: "KEEP_IDLE", title: "Garder", options: [])
        let stop = UNNotificationAction(identifier: "STOP", title: "Arrêter", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.eventCategory, actions: [start], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.idleCategory, actions: [remove, keep], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.longRunCategory, actions: [stop], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(id: String, title: String, body: String, category: String? = nil, userInfo: [String: String] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category }
        content.userInfo = userInfo
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let eventID = response.notification.request.content.userInfo["eventID"] as? String
        Task { @MainActor in self.handle(action: action, eventID: eventID) }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    private func handle(action: String, eventID: String?) {
        guard let store else { return }
        switch action {
        case "START":
            if let eventID { store.startFromEvent(eventID) } else { store.toggleTimer() }
        case "REMOVE_IDLE":
            store.removeIdle()
        case "KEEP_IDLE":
            store.keepIdle()
        case "STOP":
            store.stop()
        default:
            store.onRequestPanel?()
        }
    }
}
