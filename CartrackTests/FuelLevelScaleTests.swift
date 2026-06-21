import XCTest
@testable import Cartrack

final class FuelLevelScaleTests: XCTestCase {
    func testNormalizeRoundsToQuarterSteps() {
        XCTAssertEqual(FuelLevelScale.normalize(6.37), 6.25, accuracy: 0.001)
        XCTAssertEqual(FuelLevelScale.normalize(6.38), 6.5, accuracy: 0.001)
    }

    func testConsumedUsesSameScale() {
        XCTAssertEqual(FuelLevelScale.consumed(remaining: 6.5), 1.5, accuracy: 0.001)
    }
}
