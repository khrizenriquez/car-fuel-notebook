import XCTest
@testable import Cartrack

final class AnalyticsEngineTests: XCTestCase {
    func testFinalFillMonthAllocationPutsCycleInClosingMonth() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 20))!
        let end = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 2))!

        let firstFill = FuelFillEvent(date: start, vehicle: vehicle, odometerKilometers: 1000)
        let secondFill = FuelFillEvent(date: end, vehicle: vehicle, odometerKilometers: 1200, gallons: 10, pricePerGallon: 35, totalCost: 350)

        let summaries = AnalyticsEngine.monthlySummaries(
            fills: [firstFill, secondFill],
            adjustments: [],
            vehicleID: vehicle.id,
            mode: .finalFillMonth
        )

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(Calendar.current.component(.month, from: summaries[0].monthStart), 7)
        XCTAssertEqual(summaries[0].distanceKilometers, 200, accuracy: 0.001)
    }

    func testProratedAllocationSplitsCycleAcrossMonths() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 28))!
        let end = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 2))!

        let firstFill = FuelFillEvent(date: start, vehicle: vehicle, odometerKilometers: 1000)
        let secondFill = FuelFillEvent(date: end, vehicle: vehicle, odometerKilometers: 1200, gallons: 10, pricePerGallon: 35, totalCost: 350)

        let summaries = AnalyticsEngine.monthlySummaries(
            fills: [firstFill, secondFill],
            adjustments: [],
            vehicleID: vehicle.id,
            mode: .prorated
        )

        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries.map { $0.distanceKilometers }.reduce(0, +), 200, accuracy: 0.001)
    }

    func testManualAdjustmentAddsDistance() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let monthStart = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let adjustment = MonthlyManualAdjustment(monthStart: monthStart, vehicle: vehicle, manualDistanceKilometers: 50)

        let summaries = AnalyticsEngine.monthlySummaries(
            fills: [],
            adjustments: [adjustment],
            vehicleID: vehicle.id,
            mode: .finalFillMonth
        )

        XCTAssertEqual(summaries.first?.totalDistanceKilometers ?? -1, 50, accuracy: 0.001)
    }
}
