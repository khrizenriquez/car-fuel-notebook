import XCTest
@testable import CartrackCore

final class EventIntegrityPolicyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func reading(_ km: Decimal, day: Int, trip: Decimal? = nil,
                         id: UUID = UUID()) -> EventIntegrityReading {
        EventIntegrityReading(id: id, occurredAt: start.addingTimeInterval(Double(day) * 86_400),
                              odometerKilometers: km, tripKilometers: trip)
    }

    private func input(_ reading: EventIntegrityReading, fuel: Decimal = 4,
                       financial: EventIntegrityInput.FinancialValues? = nil,
                       reason: String = "") -> EventIntegrityInput {
        EventIntegrityInput(reading: reading, fuelLevelRemaining: fuel,
                            fuelScaleMax: 8, fuelScaleStep: Decimal(string: "0.25")!,
                            financial: financial, overrideReason: reason)
    }

    func testOdometerBoundariesAndAuditedOverride() throws {
        let old = reading(1_000, day: 1)
        let future = reading(1_200, day: 3)
        XCTAssertNoThrow(try EventIntegrityPolicy.validate(input(reading(1_000, day: 2)),
                                                          among: [old, future]))
        XCTAssertNoThrow(try EventIntegrityPolicy.validate(input(reading(1_200, day: 2)),
                                                          among: [old, future]))
        XCTAssertThrowsError(try EventIntegrityPolicy.validate(input(reading(999, day: 2)),
                                                              among: [old, future])) {
            XCTAssertEqual($0 as? EventIntegrityError, .odometerRegression)
        }
        XCTAssertThrowsError(try EventIntegrityPolicy.validate(input(reading(1_201, day: 2)),
                                                              among: [old, future]))
        let approved = try EventIntegrityPolicy.validate(
            input(reading(999, day: 2), reason: "Reparación del odómetro"), among: [old, future])
        XCTAssertTrue(approved.odometerOverrideUsed)
    }

    func testTripResetIsDetectedButNotNegativeDistance() throws {
        let result = try EventIntegrityPolicy.validate(
            input(reading(1_100, day: 2, trip: 5)),
            among: [reading(1_000, day: 1, trip: 90)])
        XCTAssertTrue(result.tripResetDetected)
        XCTAssertThrowsError(try EventIntegrityPolicy.validate(
            input(reading(1_100, day: 2, trip: -1)), among: [])) {
            XCTAssertEqual($0 as? EventIntegrityError, .invalidTrip)
        }
    }

    func testFinancialToleranceAndFuelStep() throws {
        let financial = EventIntegrityInput.FinancialValues(
            gallons: 10, unitPrice: 42, totalCost: Decimal(string: "420.05")!)
        XCTAssertNoThrow(try EventIntegrityPolicy.validate(
            input(reading(1_100, day: 2), fuel: Decimal(string: "3.25")!, financial: financial), among: []))
        let inconsistent = EventIntegrityInput.FinancialValues(gallons: 10, unitPrice: 42,
                                                                totalCost: Decimal(string: "420.06")!)
        XCTAssertThrowsError(try EventIntegrityPolicy.validate(
            input(reading(1_100, day: 2), financial: inconsistent), among: [])) {
            XCTAssertEqual($0 as? EventIntegrityError, .inconsistentFinancial)
        }
        XCTAssertThrowsError(try EventIntegrityPolicy.validate(
            input(reading(1_100, day: 2), fuel: Decimal(string: "3.1")!), among: [])) {
            XCTAssertEqual($0 as? EventIntegrityError, .invalidFuelLevel)
        }
    }

    func testEditExcludesSelfAndRespectsVehicleScopedReadings() throws {
        let current = reading(1_100, day: 2)
        XCTAssertNoThrow(try EventIntegrityPolicy.validate(input(current), among: [current]))
        XCTAssertNoThrow(try EventIntegrityPolicy.validate(input(current), among: []))
    }
}
