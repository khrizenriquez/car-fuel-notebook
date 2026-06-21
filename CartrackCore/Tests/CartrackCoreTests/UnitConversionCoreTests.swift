import XCTest
@testable import CartrackCore

final class UnitConversionCoreTests: XCTestCase {
    func testMilesToKilometersUsesStandardFactor() {
        XCTAssertEqual(UnitConversion.milesToKilometers(100), 160.9344, accuracy: 0.0001)
    }

    func testKilometersToMilesUsesStandardFactor() {
        XCTAssertEqual(UnitConversion.kilometersToMiles(160.9344), 100, accuracy: 0.0001)
    }

    func testRoundTripConversionIsStable() {
        let miles = 278.4
        XCTAssertEqual(UnitConversion.kilometersToMiles(UnitConversion.milesToKilometers(miles)), miles, accuracy: 0.0001)
    }
}
