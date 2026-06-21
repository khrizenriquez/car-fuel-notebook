import XCTest
@testable import CartrackCore

final class FuelLevelScaleCoreTests: XCTestCase {
    func testNormalizeClampsToValidRange() {
        XCTAssertEqual(FuelLevelScale.normalize(-1), 0)
        XCTAssertEqual(FuelLevelScale.normalize(9), 8)
    }

    func testNormalizeRoundsToNearestQuarterStep() {
        XCTAssertEqual(FuelLevelScale.normalize(6.37), 6.25, accuracy: 0.001)
        XCTAssertEqual(FuelLevelScale.normalize(6.38), 6.5, accuracy: 0.001)
        XCTAssertEqual(FuelLevelScale.normalize(7.99), 8, accuracy: 0.001)
    }

    func testNormalizeSupportsCustomScaleAndStep() {
        XCTAssertEqual(FuelLevelScale.normalize(9.74, maxValue: 10, step: 0.5), 9.5, accuracy: 0.001)
        XCTAssertEqual(FuelLevelScale.normalize(9.76, maxValue: 10, step: 0.5), 10, accuracy: 0.001)
    }

    func testConsumedIsDerivedFromRemaining() {
        XCTAssertEqual(FuelLevelScale.consumed(remaining: 6.5), 1.5, accuracy: 0.001)
        XCTAssertEqual(FuelLevelScale.consumed(remaining: -1), 8, accuracy: 0.001)
        XCTAssertEqual(FuelLevelScale.consumed(remaining: 9), 0, accuracy: 0.001)
    }
}
