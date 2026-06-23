import XCTest
@testable import CartrackCore

final class AnalyticsEngineCoreTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testTankCyclesUseClosingFillGallonsAndCost() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let fills = [
            fill(vehicle: vehicle, day: 1, odometer: 1_000, gallons: 10, total: 300),
            fill(vehicle: vehicle, day: 10, odometer: 1_240, gallons: 12, total: 420),
        ]

        let cycles = AnalyticsEngine.tankCycles(fills: fills, vehicleID: vehicle.id)

        XCTAssertEqual(cycles.count, 1)
        XCTAssertEqual(cycles[0].distanceKilometers, 240, accuracy: 0.001)
        XCTAssertEqual(cycles[0].gallons, 12, accuracy: 0.001)
        XCTAssertEqual(cycles[0].totalCost, 420, accuracy: 0.001)
        XCTAssertEqual(cycles[0].kmPerGallon, 20, accuracy: 0.001)
        XCTAssertEqual(cycles[0].costPerKilometer, 1.75, accuracy: 0.001)
    }

    func testTankCyclesFilterByVehicle() {
        let bmw = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let other = Vehicle(name: "Other", make: "Toyota", modelName: "Yaris", year: 2020)
        let fills = [
            fill(vehicle: bmw, day: 1, odometer: 1_000, gallons: 10, total: 300),
            fill(vehicle: bmw, day: 5, odometer: 1_100, gallons: 5, total: 175),
            fill(vehicle: other, day: 1, odometer: 2_000, gallons: 8, total: 240),
            fill(vehicle: other, day: 5, odometer: 2_080, gallons: 8, total: 240),
        ]

        XCTAssertEqual(AnalyticsEngine.tankCycles(fills: fills, vehicleID: bmw.id).count, 1)
        XCTAssertEqual(AnalyticsEngine.tankCycles(fills: fills, vehicleID: other.id).count, 1)
    }

    func testMonthlySummariesKeepVehicleDataSeparated() {
        let bmw = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let other = Vehicle(name: "Other", make: "Toyota", modelName: "Yaris", year: 2020)
        let fills = [
            fill(vehicle: bmw, day: 1, odometer: 1_000, gallons: 10, total: 300),
            fill(vehicle: bmw, day: 10, odometer: 1_240, gallons: 12, total: 420),
            fill(vehicle: other, day: 2, odometer: 5_000, gallons: 18, total: 540),
            fill(vehicle: other, day: 11, odometer: 5_500, gallons: 20, total: 700),
        ]
        let adjustments = [
            MonthlyManualAdjustment(monthStart: date(month: 6, day: 1), vehicle: bmw, manualDistanceKilometers: 25),
            MonthlyManualAdjustment(monthStart: date(month: 6, day: 1), vehicle: other, manualDistanceKilometers: 90),
        ]

        let bmwSummary = AnalyticsEngine.monthlySummaries(
            fills: fills,
            adjustments: adjustments,
            vehicleID: bmw.id,
            mode: .finalFillMonth,
            calendar: calendar
        ).first
        let otherSummary = AnalyticsEngine.monthlySummaries(
            fills: fills,
            adjustments: adjustments,
            vehicleID: other.id,
            mode: .finalFillMonth,
            calendar: calendar
        ).first

        XCTAssertEqualOptional(bmwSummary?.distanceKilometers, 240, accuracy: 0.001)
        XCTAssertEqualOptional(bmwSummary?.manualDistanceKilometers, 25, accuracy: 0.001)
        XCTAssertEqualOptional(bmwSummary?.totalDistanceKilometers, 265, accuracy: 0.001)
        XCTAssertEqualOptional(bmwSummary?.spend, 420, accuracy: 0.001)
        XCTAssertEqualOptional(bmwSummary?.gallons, 12, accuracy: 0.001)
        XCTAssertEqualOptional(bmwSummary?.kmPerGallon, 265.0 / 12.0, accuracy: 0.001)
        XCTAssertEqualOptional(otherSummary?.distanceKilometers, 500, accuracy: 0.001)
        XCTAssertEqualOptional(otherSummary?.manualDistanceKilometers, 90, accuracy: 0.001)
        XCTAssertEqualOptional(otherSummary?.spend, 700, accuracy: 0.001)
        XCTAssertEqualOptional(otherSummary?.gallons, 20, accuracy: 0.001)
    }

    func testFinalFillMonthAllocationPutsCycleInClosingMonth() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let firstFill = fill(vehicle: vehicle, month: 6, day: 20, odometer: 1_000, gallons: 10, total: 350)
        let secondFill = fill(vehicle: vehicle, month: 7, day: 2, odometer: 1_200, gallons: 10, total: 350)

        let summaries = AnalyticsEngine.monthlySummaries(
            fills: [firstFill, secondFill],
            adjustments: [],
            vehicleID: vehicle.id,
            mode: .finalFillMonth,
            calendar: calendar
        )

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(calendar.component(.month, from: summaries[0].monthStart), 7)
        XCTAssertEqual(summaries[0].distanceKilometers, 200, accuracy: 0.001)
        XCTAssertEqual(summaries[0].kmPerGallon, 20, accuracy: 0.001)
        XCTAssertEqual(summaries[0].costPerKilometer, 1.75, accuracy: 0.001)
    }

    func testProratedAllocationSplitsCycleAcrossMonthsAndPreservesTotals() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let firstFill = fill(vehicle: vehicle, month: 6, day: 28, odometer: 1_000, gallons: 10, total: 350)
        let secondFill = fill(vehicle: vehicle, month: 7, day: 2, odometer: 1_200, gallons: 10, total: 350)

        let summaries = AnalyticsEngine.monthlySummaries(
            fills: [firstFill, secondFill],
            adjustments: [],
            vehicleID: vehicle.id,
            mode: .prorated,
            calendar: calendar
        )

        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries.map(\.distanceKilometers).reduce(0, +), 200, accuracy: 0.001)
        XCTAssertEqual(summaries.map(\.spend).reduce(0, +), 350, accuracy: 0.001)
        XCTAssertEqual(summaries.map(\.gallons).reduce(0, +), 10, accuracy: 0.001)
    }

    func testManualAdjustmentAddsDistanceWithoutChangingFuelSpend() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let adjustment = MonthlyManualAdjustment(
            monthStart: date(month: 6, day: 1),
            vehicle: vehicle,
            manualDistanceKilometers: 50
        )

        let summaries = AnalyticsEngine.monthlySummaries(
            fills: [],
            adjustments: [adjustment],
            vehicleID: vehicle.id,
            mode: .finalFillMonth,
            calendar: calendar
        )

        XCTAssertEqualOptional(summaries.first?.totalDistanceKilometers, 50, accuracy: 0.001)
        XCTAssertEqualOptional(summaries.first?.spend, 0, accuracy: 0.001)
    }

    func testManualAdjustmentCanUseMilesWhenKilometersAreAbsent() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let adjustment = MonthlyManualAdjustment(
            monthStart: date(month: 6, day: 1),
            vehicle: vehicle,
            manualDistanceMiles: 10,
            manualDistanceKilometers: nil
        )

        let summaries = AnalyticsEngine.monthlySummaries(
            fills: [],
            adjustments: [adjustment],
            vehicleID: vehicle.id,
            mode: .finalFillMonth,
            calendar: calendar
        )

        XCTAssertEqualOptional(summaries.first?.totalDistanceKilometers, 16.09344, accuracy: 0.0001)
    }

    func testEditingFillValuesRecalculatesMonthlyAnalytics() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let firstFill = fill(vehicle: vehicle, day: 1, odometer: 1_000, gallons: 10, total: 300)
        let correctedFill = fill(vehicle: vehicle, day: 12, odometer: 1_240, gallons: 12, total: 420)

        var summaries = AnalyticsEngine.monthlySummaries(
            fills: [firstFill, correctedFill],
            adjustments: [],
            vehicleID: vehicle.id,
            mode: .finalFillMonth,
            calendar: calendar
        )

        XCTAssertEqualOptional(summaries.first?.distanceKilometers, 240, accuracy: 0.001)
        XCTAssertEqualOptional(summaries.first?.kmPerGallon, 20, accuracy: 0.001)
        XCTAssertEqualOptional(summaries.first?.costPerKilometer, 1.75, accuracy: 0.001)

        correctedFill.odometerKilometers = 1_300
        correctedFill.gallons = 10
        correctedFill.pricePerGallon = 35
        correctedFill.totalCost = 350

        summaries = AnalyticsEngine.monthlySummaries(
            fills: [firstFill, correctedFill],
            adjustments: [],
            vehicleID: vehicle.id,
            mode: .finalFillMonth,
            calendar: calendar
        )

        XCTAssertEqualOptional(summaries.first?.distanceKilometers, 300, accuracy: 0.001)
        XCTAssertEqualOptional(summaries.first?.kmPerGallon, 30, accuracy: 0.001)
        XCTAssertEqualOptional(summaries.first?.costPerKilometer, 350.0 / 300.0, accuracy: 0.001)
    }

    func testCurrentTankStatusUsesLatestSnapshotWhenAvailable() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let firstFill = fill(vehicle: vehicle, day: 1, odometer: 1_000, gallons: 10, total: 300)
        let secondFill = fill(vehicle: vehicle, day: 10, odometer: 1_250, gallons: 10, total: 350)
        let snapshot = SnapshotEvent(
            date: date(day: 12),
            vehicle: vehicle,
            odometerKilometers: 1_330,
            fuelLevelRemaining: 6
        )

        let status = AnalyticsEngine.currentTankStatus(
            fills: [firstFill, secondFill],
            snapshots: [snapshot],
            vehicleID: vehicle.id,
            calendar: calendar
        )

        XCTAssertEqual(status.latestFill?.id, secondFill.id)
        XCTAssertEqual(status.distanceKilometers, 80, accuracy: 0.001)
        XCTAssertEqualOptional(status.latestReadingKilometers, 1_330, accuracy: 0.001)
        XCTAssertEqualOptional(status.spacesRemaining, 6, accuracy: 0.001)
        XCTAssertEqual(status.estimatedAutonomyKilometers ?? 0, 187.5, accuracy: 0.001)
        XCTAssertEqual(status.estimatedFuelCostConsumed ?? 0, 112, accuracy: 0.001)
    }

    func testCurrentTankStatusIgnoresOtherVehicleSnapshotsAndFills() {
        let bmw = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let other = Vehicle(name: "Other", make: "Toyota", modelName: "Yaris", year: 2020)
        let bmwFirstFill = fill(vehicle: bmw, day: 1, odometer: 1_000, gallons: 10, total: 300)
        let bmwSecondFill = fill(vehicle: bmw, day: 10, odometer: 1_250, gallons: 10, total: 350)
        let otherFill = fill(vehicle: other, day: 20, odometer: 8_000, gallons: 20, total: 700)
        let bmwSnapshot = SnapshotEvent(
            date: date(day: 12),
            vehicle: bmw,
            odometerKilometers: 1_330,
            fuelLevelRemaining: 6
        )
        let otherSnapshot = SnapshotEvent(
            date: date(day: 21),
            vehicle: other,
            odometerKilometers: 8_600,
            fuelLevelRemaining: 0.5
        )

        let status = AnalyticsEngine.currentTankStatus(
            fills: [bmwFirstFill, bmwSecondFill, otherFill],
            snapshots: [bmwSnapshot, otherSnapshot],
            vehicleID: bmw.id,
            calendar: calendar
        )

        XCTAssertEqual(status.latestFill?.id, bmwSecondFill.id)
        XCTAssertEqual(status.latestReadingDate, bmwSnapshot.date)
        XCTAssertEqual(status.distanceKilometers, 80, accuracy: 0.001)
        XCTAssertEqualOptional(status.spacesRemaining, 6, accuracy: 0.001)
    }

    func testCurrentTankStatusIgnoresSnapshotsBeforeLatestFill() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let firstFill = fill(vehicle: vehicle, day: 1, odometer: 1_000, gallons: 10, total: 300)
        let staleSnapshot = SnapshotEvent(
            date: date(day: 8),
            vehicle: vehicle,
            odometerKilometers: 1_180,
            fuelLevelRemaining: 2
        )
        let secondFill = fill(vehicle: vehicle, day: 10, odometer: 1_250, gallons: 10, total: 350)

        let status = AnalyticsEngine.currentTankStatus(
            fills: [firstFill, secondFill],
            snapshots: [staleSnapshot],
            vehicleID: vehicle.id,
            calendar: calendar
        )

        XCTAssertEqual(status.latestFill?.id, secondFill.id)
        XCTAssertEqual(status.latestReadingDate, secondFill.date)
        XCTAssertEqual(status.distanceKilometers, 0, accuracy: 0.001)
        XCTAssertEqualOptional(status.spacesRemaining, FuelLevelScale.defaultMax, accuracy: 0.001)
    }

    func testCurrentTankStatusHandlesNoFillEvents() {
        let status = AnalyticsEngine.currentTankStatus(fills: [], snapshots: [], vehicleID: UUID(), calendar: calendar)

        XCTAssertNil(status.latestFill)
        XCTAssertNil(status.latestReadingDate)
        XCTAssertNil(status.latestReadingKilometers)
        XCTAssertEqual(status.distanceKilometers, 0)
        XCTAssertNil(status.spacesRemaining)
    }

    func testCurrentTankStatusUsesLatestSnapshotWhenNoFillExistsYet() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let olderSnapshot = SnapshotEvent(
            date: date(day: 12),
            vehicle: vehicle,
            odometerKilometers: 1_100,
            fuelLevelRemaining: 7
        )
        let latestSnapshot = SnapshotEvent(
            date: date(day: 13),
            vehicle: vehicle,
            odometerKilometers: 1_180,
            fuelLevelRemaining: 6.5
        )

        let status = AnalyticsEngine.currentTankStatus(
            fills: [],
            snapshots: [olderSnapshot, latestSnapshot],
            vehicleID: vehicle.id,
            calendar: calendar
        )

        XCTAssertNil(status.latestFill)
        XCTAssertEqual(status.latestReadingDate, latestSnapshot.date)
        XCTAssertEqualOptional(status.latestReadingKilometers, 1_180, accuracy: 0.001)
        XCTAssertEqual(status.distanceKilometers, 0, accuracy: 0.001)
        XCTAssertEqualOptional(status.spacesRemaining, 6.5, accuracy: 0.001)
        XCTAssertNil(status.estimatedAutonomyKilometers)
        XCTAssertNil(status.estimatedFuelCostConsumed)
    }

    func testMonthlyPurchasesSummarizeOpenMonthFillSpendWithoutClosingCycle() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let currentFill = fill(vehicle: vehicle, day: 12, odometer: 1_000, gallons: 11.3468, total: 394.30)
        let previousFill = fill(vehicle: vehicle, month: 5, day: 30, odometer: 900, gallons: 10, total: 300)

        let purchases = AnalyticsEngine.monthlyPurchases(
            fills: [previousFill, currentFill],
            vehicleID: vehicle.id,
            monthStart: date(month: 6, day: 1),
            calendar: calendar
        )

        XCTAssertEqual(purchases.fillCount, 1)
        XCTAssertEqual(purchases.spend, 394.30, accuracy: 0.001)
        XCTAssertEqual(purchases.gallons, 11.3468, accuracy: 0.001)
    }

    func testMonthlyProjectionScalesCurrentMonthPace() throws {
        let summary = MonthlySummary(
            id: date(month: 6, day: 1),
            monthStart: date(month: 6, day: 1),
            vehicleID: UUID(),
            spend: 300,
            gallons: 10,
            distanceKilometers: 240,
            cycleCount: 1,
            manualDistanceKilometers: 60
        )
        let now = date(month: 6, day: 15)

        let projection = try XCTUnwrap(AnalyticsEngine.monthlyProjection(from: summary, now: now, calendar: calendar))

        XCTAssertEqual(projection.elapsedDays, 15)
        XCTAssertEqual(projection.totalDays, 30)
        XCTAssertEqual(projection.projectedSpend, 600, accuracy: 0.001)
        XCTAssertEqual(projection.projectedGallons, 20, accuracy: 0.001)
        XCTAssertEqual(projection.projectedDistanceKilometers, 600, accuracy: 0.001)
        XCTAssertEqual(projection.projectedKmPerGallon, 30, accuracy: 0.001)
        XCTAssertEqual(projection.projectedCostPerKilometer, 1, accuracy: 0.001)
    }

    func testMonthlyProjectionIgnoresNonCurrentMonth() {
        let summary = MonthlySummary(
            id: date(month: 5, day: 1),
            monthStart: date(month: 5, day: 1),
            vehicleID: UUID(),
            spend: 300,
            gallons: 10,
            distanceKilometers: 240,
            cycleCount: 1,
            manualDistanceKilometers: 0
        )

        XCTAssertNil(AnalyticsEngine.monthlyProjection(from: summary, now: date(month: 6, day: 15), calendar: calendar))
    }

    private func fill(
        vehicle: Vehicle,
        month: Int = 6,
        day: Int,
        odometer: Double,
        gallons: Double,
        total: Double
    ) -> FuelFillEvent {
        FuelFillEvent(
            date: date(month: month, day: day),
            vehicle: vehicle,
            odometerKilometers: odometer,
            gallons: gallons,
            pricePerGallon: gallons > 0 ? total / gallons : 0,
            totalCost: total
        )
    }

    private func date(month: Int = 6, day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }
}
