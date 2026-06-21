import Foundation
import UserNotifications

final class ReminderService: @unchecked Sendable {
    static let shared = ReminderService()
    private let center = UNUserNotificationCenter.current()
    private let identifier = "cartrack.inactivity.reminder"

    private init() {}

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func scheduleInactivityReminder(afterHours hours: Double) async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard hours > 0 else { return }

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
