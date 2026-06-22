import Foundation
import UserNotifications

protocol ReminderNotificationCenter {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func add(_ request: UNNotificationRequest) async throws
}

extension UNUserNotificationCenter: ReminderNotificationCenter {}

final class ReminderService: @unchecked Sendable {
    static let shared = ReminderService()
    private let center: ReminderNotificationCenter
    private let identifier: String

    init(
        center: ReminderNotificationCenter = UNUserNotificationCenter.current(),
        identifier: String = "cartrack.inactivity.reminder"
    ) {
        self.center = center
        self.identifier = identifier
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func cancelInactivityReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func captureLogged(userDefaults: UserDefaults = .standard) async {
        let enabled = userDefaults.object(forKey: "settings.reminder.enabled").map { _ in
            userDefaults.bool(forKey: "settings.reminder.enabled")
        } ?? true
        let hours = userDefaults.double(forKey: "settings.reminder.hours").nonZeroOrDefault(72)
        await refreshInactivityReminder(isEnabled: enabled, afterHours: hours)
    }

    func refreshInactivityReminder(isEnabled: Bool, afterHours hours: Double) async {
        cancelInactivityReminder()
        guard isEnabled, hours > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Cartrack"
        content.body = "Hace tiempo que no registras una lectura. Toma una foto del tablero o factura para mantener tu historial."
        content.sound = .default

        let seconds = max(3_600, hours * 3_600)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
