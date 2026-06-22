import UserNotifications
import XCTest
@testable import Cartrack

final class ReminderServiceTests: XCTestCase {
    func testCaptureLoggedSchedulesDefaultReminderWhenPreferenceIsMissing() async {
        let center = FakeReminderNotificationCenter()
        let service = ReminderService(center: center)
        let userDefaults = makeIsolatedUserDefaults()

        await service.captureLogged(userDefaults: userDefaults)

        XCTAssertEqual(center.removedIdentifiers, [["cartrack.inactivity.reminder"]])
        XCTAssertEqual(center.addedRequests.count, 1)
        XCTAssertEqual(center.addedRequests.first?.identifier, "cartrack.inactivity.reminder")
        assertTimeInterval(center.addedRequests.first?.timeInterval, equals: 72 * 3_600)
    }

    func testCaptureLoggedCancelsReminderWhenDisabled() async {
        let center = FakeReminderNotificationCenter()
        let service = ReminderService(center: center)
        let userDefaults = makeIsolatedUserDefaults()
        userDefaults.set(false, forKey: "settings.reminder.enabled")
        userDefaults.set(24.0, forKey: "settings.reminder.hours")

        await service.captureLogged(userDefaults: userDefaults)

        XCTAssertEqual(center.removedIdentifiers, [["cartrack.inactivity.reminder"]])
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testCaptureLoggedResetsReminderAfterEachNewCapture() async {
        let center = FakeReminderNotificationCenter()
        let service = ReminderService(center: center)
        let userDefaults = makeIsolatedUserDefaults()
        userDefaults.set(true, forKey: "settings.reminder.enabled")

        userDefaults.set(24.0, forKey: "settings.reminder.hours")
        await service.captureLogged(userDefaults: userDefaults)
        userDefaults.set(48.0, forKey: "settings.reminder.hours")
        await service.captureLogged(userDefaults: userDefaults)

        XCTAssertEqual(center.removedIdentifiers.count, 2)
        XCTAssertEqual(center.addedRequests.count, 2)
        assertTimeInterval(center.addedRequests.last?.timeInterval, equals: 48 * 3_600)
    }

    func testRefreshInactivityReminderTreatsShortIntervalsAsOneHourMinimum() async {
        let center = FakeReminderNotificationCenter()
        let service = ReminderService(center: center)

        await service.refreshInactivityReminder(isEnabled: true, afterHours: 0.25)

        assertTimeInterval(center.addedRequests.first?.timeInterval, equals: 3_600)
    }

    private func makeIsolatedUserDefaults(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> UserDefaults {
        let suiteName = "com.duku.cartrack.tests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults", file: file, line: line)
            return .standard
        }
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    private func assertTimeInterval(
        _ actual: TimeInterval?,
        equals expected: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Expected notification trigger time interval", file: file, line: line)
            return
        }
        XCTAssertEqual(actual, expected, accuracy: 0.001, file: file, line: line)
    }
}

private final class FakeReminderNotificationCenter: ReminderNotificationCenter {
    struct AddedRequest {
        let identifier: String
        let timeInterval: TimeInterval?
    }

    private(set) var authorizationOptions: [UNAuthorizationOptions] = []
    private(set) var removedIdentifiers: [[String]] = []
    private(set) var addedRequests: [AddedRequest] = []

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationOptions.append(options)
        return true
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(identifiers)
    }

    func add(_ request: UNNotificationRequest) async throws {
        let trigger = request.trigger as? UNTimeIntervalNotificationTrigger
        addedRequests.append(AddedRequest(identifier: request.identifier, timeInterval: trigger?.timeInterval))
    }
}
