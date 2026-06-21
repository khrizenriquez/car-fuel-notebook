import XCTest
@testable import CartrackCore

final class StringAndDateCoreTests: XCTestCase {
    func testTrimmedRemovesWhitespace() {
        XCTAssertEqual("  BMW Z4\n".trimmed, "BMW Z4")
    }

    func testAsDoubleAcceptsCommaDecimalSeparator() {
        XCTAssertEqual("32,10".asDouble, 32.10)
        XCTAssertEqual(" 10.2500 ".asDouble, 10.2500)
        XCTAssertNil("abc".asDouble)
    }

    func testOptionalNilIfBlank() {
        XCTAssertNil(Optional("   ").nilIfBlank)
        XCTAssertEqual(Optional("Z4").nilIfBlank, "Z4")
    }

    func testStartOfMonthUsesCalendarMonthStart() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 15))!
        let start = date.startOfMonth(using: calendar)

        XCTAssertEqual(calendar.component(.year, from: start), 2026)
        XCTAssertEqual(calendar.component(.month, from: start), 6)
        XCTAssertEqual(calendar.component(.day, from: start), 1)
    }

    func testFormattedMonthIncludesYear() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        XCTAssertTrue(date.formattedMonth(using: calendar).contains("2026"))
    }
}
