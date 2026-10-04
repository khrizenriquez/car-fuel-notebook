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

    func testTankCyclesAccumulatePartialFillWithoutClosingCycle() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let fills = [
            fill(vehicle: vehicle, day: 1, odometer: 1_000, gallons: 10, total: 300, isFullTank: true),
            fill(vehicle: vehicle, day: 5, odometer: 1_120, gallons: 4, total: 140, isFullTank: false),
            fill(vehicle: vehicle, day: 10, odometer: 1_240, gallons: 12, total: 420, isFullTank: true),
        ]

        let cycles = AnalyticsEngine.tankCycles(fills: fills, vehicleID: vehicle.id)

        XCTAssertEqual(cycles.count, 1)
        XCTAssertEqual(cycles[0].distanceKilometers, 240, accuracy: 0.001)
        XCTAssertEqual(cycles[0].gallons, 16, accuracy: 0.001)
        XCTAssertEqual(cycles[0].totalCost, 560, accuracy: 0.001)
        XCTAssertEqual(cycles[0].kmPerGallon, 15, accuracy: 0.001)
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
        XCTAssertEqual(status.estimatedAutonomyKilometers ?? 0, 262.5, accuracy: 0.001)
        XCTAssertEqual(status.estimatedFuelCostConsumed ?? 0, 112, accuracy: 0.001)
    }

    func testCurrentTankInsightMatchesLatestBMWZ4ReferenceMeasurements() throws {
        let vehicle = Vehicle(
            name: "BMW",
            make: "BMW",
            modelName: "Z4",
            year: 2003,
            fuelScaleMax: 8,
            fuelScaleStep: 0.25
        )
        let fillA = fill(vehicle: vehicle, day: 1, odometer: 1_000, gallons: 11, total: 385)
        let fillB = fill(vehicle: vehicle, day: 8, odometer: 1_400, gallons: 11, total: 385)
        let fillC = fill(vehicle: vehicle, day: 15, odometer: 1_805, gallons: 11, total: 385)
        let latestFullFill = fill(vehicle: vehicle, day: 22, odometer: 2_220, gallons: 11, total: 385)
        let previousSnapshot = SnapshotEvent(
            date: date(day: 24),
            vehicle: vehicle,
            odometerMilesOriginal: 108_288,
            odometerKilometers: 2_220 + 204.2,
            tripMilesOriginal: 126.9,
            tripKilometers: 204.2,
            fuelLevelRemaining: 5.5
        )
        let latestSnapshot = SnapshotEvent(
            date: date(day: 26),
            vehicle: vehicle,
            odometerMilesOriginal: 108_335,
            odometerKilometers: 2_220 + 279.5,
            tripMilesOriginal: 173.7,
            tripKilometers: 279.5,
            fuelLevelRemaining: 4.5
        )

        let status = AnalyticsEngine.currentTankStatus(
            fills: [fillA, fillB, fillC, latestFullFill],
            snapshots: [previousSnapshot, latestSnapshot],
            vehicleID: vehicle.id,
            calendar: calendar
        )
        let insight: CurrentTankInsight = try XCTUnwrap(status.insight)

        XCTAssertEqual(status.distanceKilometers, 279.5, accuracy: 0.001)
        XCTAssertEqualOptional(insight.latestOdometerMiles, 108_335, accuracy: 0.001)
        XCTAssertEqualOptional(insight.latestTripMiles, 173.7, accuracy: 0.001)
        XCTAssertEqualOptional(insight.latestTripKilometers, 279.5, accuracy: 0.001)
        XCTAssertEqualOptional(insight.previousTripMiles, 126.9, accuracy: 0.001)
        XCTAssertEqualOptional(insight.previousTripKilometers, 204.2, accuracy: 0.001)
        XCTAssertEqualOptional(insight.tripDeltaMiles, 46.8, accuracy: 0.001)
        XCTAssertEqualOptional(insight.tripDeltaKilometers, 75.3, accuracy: 0.001)
        XCTAssertEqualOptional(insight.fuelSpacesConsumed, 3.5, accuracy: 0.001)
        XCTAssertEqualOptional(insight.fuelRemainingRatio, 0.5625, accuracy: 0.001)
        XCTAssertEqualOptional(insight.likelyTankRangeLowerKilometers, 400, accuracy: 0.001)
        XCTAssertEqualOptional(insight.likelyTankRangeUpperKilometers, 415, accuracy: 0.001)
        XCTAssertEqualOptional(insight.likelyTankRangeKilometers, 406.6667, accuracy: 0.001)
        XCTAssertEqualOptional(insight.remainingRangeLowerKilometers, 120.5, accuracy: 0.001)
        XCTAssertEqualOptional(insight.remainingRangeUpperKilometers, 135.5, accuracy: 0.001)

        let copy = CurrentTankInsightFormatter.copy(for: insight, vehicleName: "BMW Z4 2.5i")
        XCTAssertEqual(copy.state, """
        Trip: 173.7 millas = 279.5 km
        Odometro: 108,335 millas
        Nivel de combustible: aproximadamente 3.5 espacios consumidos, queda alrededor del 60% del tanque
        """)
        XCTAssertEqual(copy.comparison, """
        Medicion anterior: 126.9 millas (204.2 km)
        Ahora: 173.7 millas (279.5 km)
        Recorrido desde entonces: 46.8 millas = 75.3 km
        La aguja del Z4 puede bajar de forma no lineal, asi que una pequena variacion adicional es normal.
        """)
        XCTAssertEqual(copy.estimate, """
        Autonomia total real: 400-415 km
        Lo mas probable: ≈405 km por tanque
        Combustible restante: 120-140 km antes de llegar a reserva
        Referencia de gasto: Q 385.00 / 279.5 km = Q 1.38/km
        Patron actual: BMW Z4 2.5i esta mostrando alrededor de 400-410 km por tanque lleno en tu uso real.
        """)
    }

    func testCurrentTankInsightSummarizesReserveReadingInMilesAndKilometers() throws {
        let vehicle = Vehicle(
            name: "Z4",
            make: "BMW",
            modelName: "Z4",
            year: 2003,
            tankCapacityGallons: 14.0,
            fuelScaleMax: 8,
            fuelScaleStep: 0.25,
            fuelEconomyReferenceKilometersPerGallon: 29.0
        )
        let fillOdometerMiles = 109_162.0
        let latestOdometerMiles = 109_413.0
        let fullFill = FuelFillEvent(
            date: date(day: 10),
            vehicle: vehicle,
            odometerMilesOriginal: fillOdometerMiles,
            odometerKilometers: UnitConversion.milesToKilometers(fillOdometerMiles),
            tripMilesOriginal: 0,
            tripKilometers: 0,
            gallons: 3.791,
            pricePerGallon: 39.57,
            totalCost: 150,
            isFullTank: true,
            fuelLevelRemaining: 8
        )
        let previousSnapshot = SnapshotEvent(
            date: date(day: 12),
            vehicle: vehicle,
            odometerMilesOriginal: 109_393.9,
            odometerKilometers: UnitConversion.milesToKilometers(109_393.9),
            tripMilesOriginal: 232.9,
            tripKilometers: UnitConversion.milesToKilometers(232.9),
            fuelLevelRemaining: 1.5
        )
        let reserveSnapshot = SnapshotEvent(
            date: date(day: 13),
            vehicle: vehicle,
            odometerMilesOriginal: latestOdometerMiles,
            odometerKilometers: UnitConversion.milesToKilometers(latestOdometerMiles),
            tripMilesOriginal: 251.0,
            tripKilometers: UnitConversion.milesToKilometers(251.0),
            fuelLevelRemaining: 1.0
        )

        let status = AnalyticsEngine.currentTankStatus(
            fills: [fullFill],
            snapshots: [previousSnapshot, reserveSnapshot],
            vehicleID: vehicle.id,
            calendar: calendar
        )
        let insight: CurrentTankInsight = try XCTUnwrap(status.insight)
        let copy = CurrentTankInsightFormatter.copy(for: insight, vehicleName: "BMW Z4 2.5i")

        XCTAssertEqual(status.distanceKilometers, UnitConversion.milesToKilometers(251.0), accuracy: 0.1)
        XCTAssertEqualOptional(insight.latestOdometerMiles, 109_413, accuracy: 0.001)
        XCTAssertEqualOptional(insight.latestTripMiles, 251.0, accuracy: 0.001)
        XCTAssertEqualOptional(insight.latestTripKilometers, 403.9, accuracy: 0.1)
        XCTAssertEqualOptional(insight.previousTripMiles, 232.9, accuracy: 0.001)
        XCTAssertEqualOptional(insight.tripDeltaMiles, 18.1, accuracy: 0.001)
        XCTAssertEqualOptional(insight.tripDeltaKilometers, 29.1, accuracy: 0.1)
        XCTAssertEqualOptional(insight.remainingRangeLowerKilometers, 49.5, accuracy: 0.1)
        XCTAssertEqualOptional(insight.remainingRangeUpperKilometers, 52.0, accuracy: 0.1)
        XCTAssertEqualOptional(insight.currentCostPerKilometer, 150 / UnitConversion.milesToKilometers(251.0), accuracy: 0.001)
        XCTAssertTrue(copy.state.contains("Trip: 251.0 millas = 403.9 km"))
        XCTAssertTrue(copy.state.contains("Odometro: 109,413 millas"))
        XCTAssertTrue(copy.comparison?.contains("Recorrido desde entonces: 18.1 millas = 29.1 km") == true)
        XCTAssertTrue(copy.estimate?.contains("Combustible restante: 45-55 km de autonomia estimada") == true)
        let normalizedEstimate = copy.estimate?.replacingOccurrences(of: "\u{00A0}", with: "")
        XCTAssertTrue(normalizedEstimate?.contains("Q150.00 / 403.9 km = Q0.37/km") == true)
    }

    func testCurrentTankStatusKeepsLastFullFillAsBaselineAfterPartialTopUp() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let firstFill = fill(vehicle: vehicle, day: 1, odometer: 1_000, gallons: 10, total: 300, isFullTank: true)
        let secondFill = fill(vehicle: vehicle, day: 10, odometer: 1_250, gallons: 10, total: 350, isFullTank: true)
        let partialFill = fill(vehicle: vehicle, day: 14, odometer: 1_330, gallons: 4, total: 148, isFullTank: false)
        let snapshot = SnapshotEvent(
            date: date(day: 16),
            vehicle: vehicle,
            odometerKilometers: 1_360,
            fuelLevelRemaining: 6
        )

        let status = AnalyticsEngine.currentTankStatus(
            fills: [firstFill, secondFill, partialFill],
            snapshots: [snapshot],
            vehicleID: vehicle.id,
            calendar: calendar
        )

        XCTAssertEqual(status.latestFill?.id, secondFill.id)
        XCTAssertEqual(status.distanceKilometers, 110, accuracy: 0.001)
        XCTAssertEqualOptional(status.latestReadingKilometers, 1_360, accuracy: 0.001)
        XCTAssertEqualOptional(status.spacesRemaining, 6, accuracy: 0.001)
    }

    func testCurrentTankStatusUsesVehicleTankCapacityAndReferenceWhenNoClosedCycleExistsYet() {
        let vehicle = Vehicle(
            name: "BMW",
            make: "BMW",
            modelName: "Z4",
            year: 2003,
            tankCapacityGallons: 14,
            fuelEconomyReferenceKilometersPerGallon: 24.5
        )
        let firstFullFill = fill(vehicle: vehicle, day: 10, odometer: 1_250, gallons: 11.3468, total: 451.03, isFullTank: true)
        let snapshot = SnapshotEvent(
            date: date(day: 12),
            vehicle: vehicle,
            odometerKilometers: 1_367.5,
            fuelLevelRemaining: 1.5
        )

        let status = AnalyticsEngine.currentTankStatus(
            fills: [firstFullFill],
            snapshots: [snapshot],
            vehicleID: vehicle.id,
            calendar: calendar
        )

        XCTAssertEqual(status.distanceKilometers, 117.5, accuracy: 0.001)
        XCTAssertEqualOptional(status.spacesRemaining, 1.5, accuracy: 0.001)
        XCTAssertEqual(status.estimatedAutonomyKilometers ?? 0, 64.3125, accuracy: 0.001)
        XCTAssertEqual(status.estimatedFuelCostConsumed ?? 0, 190.6355149667, accuracy: 0.001)
    }

    func testCurrentTankStatusWithoutFullFillUsesLatestCaptureOnly() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let partialFill = fill(vehicle: vehicle, day: 5, odometer: 1_120, gallons: 4, total: 140, isFullTank: false)
        let snapshot = SnapshotEvent(
            date: date(day: 7),
            vehicle: vehicle,
            odometerKilometers: 1_180,
            fuelLevelRemaining: 5.5
        )

        let status = AnalyticsEngine.currentTankStatus(
            fills: [partialFill],
            snapshots: [snapshot],
            vehicleID: vehicle.id,
            calendar: calendar
        )

        XCTAssertNil(status.latestFill)
        XCTAssertEqual(status.latestReadingDate, snapshot.date)
        XCTAssertEqualOptional(status.latestReadingKilometers, 1_180, accuracy: 0.001)
        XCTAssertEqual(status.distanceKilometers, 0, accuracy: 0.001)
        XCTAssertEqualOptional(status.spacesRemaining, 5.5, accuracy: 0.001)
        XCTAssertNil(status.estimatedAutonomyKilometers)
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
        let currentFill = fill(vehicle: vehicle, day: 12, odometer: 1_000, gallons: 12.5, total: 412.75)
        let previousFill = fill(vehicle: vehicle, month: 5, day: 30, odometer: 900, gallons: 10, total: 300)

        let purchases = AnalyticsEngine.monthlyPurchases(
            fills: [previousFill, currentFill],
            vehicleID: vehicle.id,
            monthStart: date(month: 6, day: 1),
            calendar: calendar
        )

        XCTAssertEqual(purchases.fillCount, 1)
        XCTAssertEqual(purchases.spend, 412.75, accuracy: 0.001)
        XCTAssertEqual(purchases.gallons, 12.5, accuracy: 0.001)
        XCTAssertEqualOptional(purchases.averagePricePerGallon, 33.02, accuracy: 0.001)
        XCTAssertEqual(purchases.liters, UnitConversion.gallonsToLiters(12.5), accuracy: 0.001)
    }

    func testLocalDataRepairCorrectsReceiptDecimalGallonsSavedAsThousands() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let fill = fill(vehicle: vehicle, day: 12, odometer: 1_000, gallons: 3_791, total: 150)
        fill.pricePerGallon = 39.57

        let repaired = LocalDataRepairService.repairReceiptDecimalArtifacts(fills: [fill], now: date(day: 13))

        XCTAssertEqual(repaired, 1)
        XCTAssertEqual(fill.gallons, 150 / 39.57, accuracy: 0.0001)
        XCTAssertEqualOptional(AnalyticsEngine.monthlyPurchases(
            fills: [fill],
            vehicleID: vehicle.id,
            monthStart: date(day: 1),
            calendar: calendar
        ).averagePricePerGallon, 39.57, accuracy: 0.001)
    }

    func testWeeklyPurchasesSummarizeOpenWeekFillSpendWithoutClosingCycle() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let currentFill = fill(vehicle: vehicle, day: 12, odometer: 1_000, gallons: 11.3, total: 394.30)
        let earlierWeekFill = fill(vehicle: vehicle, day: 4, odometer: 920, gallons: 10, total: 320)

        let purchases = AnalyticsEngine.weeklyPurchases(
            fills: [earlierWeekFill, currentFill],
            vehicleID: vehicle.id,
            weekStart: date(day: 8),
            calendar: calendar
        )

        XCTAssertEqual(purchases.fillCount, 1)
        XCTAssertEqual(purchases.spend, 394.30, accuracy: 0.001)
        XCTAssertEqual(purchases.gallons, 11.3, accuracy: 0.001)
        XCTAssertEqualOptional(purchases.averagePricePerGallon, 394.30 / 11.3, accuracy: 0.001)
    }

    func testMonthlyCapturesExposeSnapshotOnlyActivityForDashboard() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let snapshot = SnapshotEvent(
            date: date(day: 22),
            vehicle: vehicle,
            odometerKilometers: 173_599.9,
            tripKilometers: UnitConversion.milesToKilometers(73),
            fuelLevelRemaining: 8
        )

        let captures = AnalyticsEngine.monthlyCaptures(
            fills: [],
            snapshots: [snapshot],
            vehicleID: vehicle.id,
            monthStart: date(month: 6, day: 1),
            calendar: calendar
        )

        XCTAssertEqual(captures.fillCount, 0)
        XCTAssertEqual(captures.snapshotCount, 1)
        XCTAssertEqual(captures.totalCaptureCount, 1)
        XCTAssertEqual(captures.latestCaptureDate, snapshot.date)
        XCTAssertEqualOptional(captures.latestSnapshotTripKilometers, UnitConversion.milesToKilometers(73), accuracy: 0.001)
        XCTAssertEqualOptional(captures.latestSnapshotOdometerKilometers, 173_599.9, accuracy: 0.001)
        XCTAssertEqualOptional(captures.latestSnapshotFuelLevelRemaining, 8, accuracy: 0.001)
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

    func testWeeklySummariesGroupClosedCyclesByWeek() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let fills = [
            fill(vehicle: vehicle, month: 6, day: 1, odometer: 1_000, gallons: 10, total: 300),
            fill(vehicle: vehicle, month: 6, day: 6, odometer: 1_240, gallons: 12, total: 420),
            fill(vehicle: vehicle, month: 6, day: 10, odometer: 1_500, gallons: 11, total: 385),
        ]

        let summaries = AnalyticsEngine.weeklySummaries(
            fills: fills,
            vehicleID: vehicle.id,
            calendar: calendar
        )

        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries[0].distanceKilometers, 260, accuracy: 0.001)
        XCTAssertEqual(summaries[0].gallons, 11, accuracy: 0.001)
        XCTAssertEqual(summaries[0].spend, 385, accuracy: 0.001)
        XCTAssertEqual(summaries[0].kmPerGallon, 260.0 / 11.0, accuracy: 0.001)
        XCTAssertEqual(summaries[1].distanceKilometers, 240, accuracy: 0.001)
        XCTAssertEqual(summaries[1].gallons, 12, accuracy: 0.001)
        XCTAssertEqual(summaries[1].spend, 420, accuracy: 0.001)
    }

    func testDetailedWeeklyReportsUseClosedCyclesAsRealValues() throws {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let fills = [
            fill(vehicle: vehicle, month: 6, day: 1, odometer: 1_000, gallons: 10, total: 300),
            fill(vehicle: vehicle, month: 6, day: 6, odometer: 1_240, gallons: 12, total: 420),
        ]

        let report = try XCTUnwrap(
            AnalyticsEngine.detailedWeeklyReports(
                fills: fills,
                snapshots: [],
                vehicleID: vehicle.id,
                calendar: calendar
            ).first
        )

        XCTAssertEqual(report.valueOrigin, .real)
        XCTAssertEqual(report.distanceKilometers, 240, accuracy: 0.001)
        XCTAssertEqualOptional(report.gallons, 12, accuracy: 0.001)
        XCTAssertEqualOptional(report.totalCost, 420, accuracy: 0.001)
        XCTAssertEqualOptional(report.kmPerGallon, 20, accuracy: 0.001)
        XCTAssertEqual(report.daysOfUse, 2)
        XCTAssertEqual(report.averageDailyKilometers, 120, accuracy: 0.001)
        XCTAssertEqual(report.cycleCount, 1)
    }

    func testDetailedWeeklyReportsEstimateOpenTankWhenOnlyReadingsExist() throws {
        let vehicle = Vehicle(
            name: "BMW",
            make: "BMW",
            modelName: "Z4",
            year: 2003,
            tankCapacityGallons: 14,
            fuelEconomyReferenceKilometersPerGallon: 24.5
        )
        let firstFullFill = fill(vehicle: vehicle, day: 10, odometer: 1_250, gallons: 11.3468, total: 451.03, isFullTank: true)
        let snapshot = SnapshotEvent(
            date: date(day: 12),
            vehicle: vehicle,
            odometerKilometers: 1_367.5,
            fuelLevelRemaining: 1.5
        )

        let report = try XCTUnwrap(
            AnalyticsEngine.detailedWeeklyReports(
                fills: [firstFullFill],
                snapshots: [snapshot],
                vehicleID: vehicle.id,
                calendar: calendar
            ).first
        )

        XCTAssertEqual(report.valueOrigin, .estimated)
        XCTAssertEqual(report.distanceKilometers, 117.5, accuracy: 0.001)
        XCTAssertEqualOptional(report.gallons, 117.5 / 24.5, accuracy: 0.001)
        XCTAssertEqualOptional(report.kmPerGallon, 24.5, accuracy: 0.001)
        XCTAssertEqualOptional(report.totalCost, 117.5 / 24.5 * firstFullFill.pricePerGallon, accuracy: 0.001)
        XCTAssertEqual(report.daysOfUse, 2)
        XCTAssertEqual(report.averageDailyKilometers, 58.75, accuracy: 0.001)
    }

    func testDetailedMonthlyReportsCombinePaidCyclesAndCurrentTankProgress() throws {
        let vehicle = Vehicle(
            name: "BMW",
            make: "BMW",
            modelName: "Z4",
            year: 2003,
            tankCapacityGallons: 14,
            fuelEconomyReferenceKilometersPerGallon: 24.5
        )
        let fills = [
            fill(vehicle: vehicle, day: 1, odometer: 1_000, gallons: 10, total: 300),
            fill(vehicle: vehicle, day: 10, odometer: 1_250, gallons: 10, total: 350),
        ]
        let snapshot = SnapshotEvent(
            date: date(day: 12),
            vehicle: vehicle,
            odometerKilometers: 1_330,
            fuelLevelRemaining: 6
        )

        let report = try XCTUnwrap(
            AnalyticsEngine.detailedMonthlyReports(
                fills: fills,
                snapshots: [snapshot],
                adjustments: [],
                vehicleID: vehicle.id,
                mode: .finalFillMonth,
                calendar: calendar,
                now: date(day: 15)
            ).first
        )

        XCTAssertEqual(report.fillCount, 2)
        XCTAssertEqual(report.totalPaid, 650, accuracy: 0.001)
        XCTAssertEqual(report.distanceKilometers, 330, accuracy: 0.001)
        XCTAssertEqual(report.consumptionOrigin, .mixed)
        XCTAssertEqualOptional(report.gallonsConsumed, 13.2, accuracy: 0.001)
        XCTAssertEqualOptional(report.kmPerGallon, 25, accuracy: 0.001)
        XCTAssertEqualOptional(report.costPerKilometer, 650.0 / 330.0, accuracy: 0.001)
        XCTAssertEqualOptional(report.averageAutonomyKilometers, 350, accuracy: 0.001)
        XCTAssertEqualOptional(report.estimatedConsumedCost, 429, accuracy: 0.001)
        XCTAssertEqualOptional(report.paidVsConsumedDelta, 221, accuracy: 0.001)
        XCTAssertEqualOptional(report.bestTank?.kmPerGallon, 25, accuracy: 0.001)
        XCTAssertEqualOptional(report.worstTank?.kmPerGallon, 25, accuracy: 0.001)
        XCTAssertEqual(report.daysOfUse, 3)
        XCTAssertEqual(report.averageDailyKilometers, 110, accuracy: 0.001)
    }

    func testTankComparisonReportsMarkBestAndWorstClosedTanks() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let fills = [
            fill(vehicle: vehicle, day: 1, odometer: 1_000, gallons: 10, total: 300),
            fill(vehicle: vehicle, day: 10, odometer: 1_250, gallons: 10, total: 350),
            fill(vehicle: vehicle, day: 20, odometer: 1_450, gallons: 12, total: 420),
        ]

        let comparisons = AnalyticsEngine.tankComparisonReports(
            fills: fills,
            vehicleID: vehicle.id
        )

        XCTAssertEqual(comparisons.count, 2)
        XCTAssertEqual(comparisons[0].distanceKilometers, 200, accuracy: 0.001)
        XCTAssertEqual(comparisons[0].openingOdometerKilometers, 1_250, accuracy: 0.001)
        XCTAssertEqual(comparisons[0].closingOdometerKilometers, 1_450, accuracy: 0.001)
        XCTAssertTrue(comparisons[1].isBest)
        XCTAssertTrue(comparisons[0].isWorst)
    }

    func testDetailedReportCSVRowsExposeHeadersAndOrigins() {
        let weekly = DetailedWeeklyReport(
            id: date(day: 8).startOfWeek(using: calendar),
            weekStart: date(day: 8).startOfWeek(using: calendar),
            vehicleID: UUID(),
            distanceKilometers: 117.5,
            gallons: 4.795918367,
            totalCost: 190.6355,
            kmPerGallon: 24.5,
            daysOfUse: 2,
            averageDailyKilometers: 58.75,
            cycleCount: 0,
            valueOrigin: .estimated
        )
        let monthly = DetailedMonthlyReport(
            id: date(day: 1).startOfMonth(using: calendar),
            monthStart: date(day: 1).startOfMonth(using: calendar),
            vehicleID: UUID(),
            fillCount: 2,
            totalPaid: 650,
            distanceKilometers: 330,
            gallonsConsumed: 13.2,
            consumptionOrigin: .mixed,
            costPerKilometer: 1.969696,
            averageAutonomyKilometers: 350,
            bestTank: nil,
            worstTank: nil,
            estimatedConsumedCost: 429,
            paidVsConsumedDelta: 221,
            cycleCount: 1,
            daysOfUse: 3,
            averageDailyKilometers: 110
        )

        let weeklyRows = AnalyticsEngine.weeklyReportCSVRows([weekly])
        let monthlyRows = AnalyticsEngine.monthlyReportCSVRows([monthly])

        XCTAssertEqual(weeklyRows[0][0], "semana_inicio")
        XCTAssertEqual(weeklyRows[1][8], "estimated")
        XCTAssertEqual(weeklyRows[1][1], "117.5000")
        XCTAssertEqual(monthlyRows[0][0], "mes_inicio")
        XCTAssertEqual(monthlyRows[1][15], "mixed")
        XCTAssertEqual(monthlyRows[1][3], "330.0000")
    }

    func testDetailedWeeklyReportsAggregateAcrossVehiclesWhenFilterIsNil() throws {
        let bmw = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003)
        let toyota = Vehicle(
            name: "Commuter",
            make: "Toyota",
            modelName: "Yaris",
            year: 2020,
            fuelEconomyReferenceKilometersPerGallon: 20
        )
        let fills = [
            fill(vehicle: bmw, day: 1, odometer: 1_000, gallons: 10, total: 300),
            fill(vehicle: bmw, day: 6, odometer: 1_240, gallons: 12, total: 420),
            fill(vehicle: toyota, day: 2, odometer: 5_000, gallons: 18, total: 540),
        ]
        let snapshots = [
            SnapshotEvent(
                date: date(day: 4),
                vehicle: toyota,
                odometerKilometers: 5_120,
                fuelLevelRemaining: 7
            )
        ]

        let report = try XCTUnwrap(
            AnalyticsEngine.detailedWeeklyReports(
                fills: fills,
                snapshots: snapshots,
                vehicleID: nil,
                calendar: calendar
            ).first
        )

        XCTAssertEqual(report.valueOrigin, .mixed)
        XCTAssertEqual(report.distanceKilometers, 360, accuracy: 0.001)
        XCTAssertEqualOptional(report.gallons, 18, accuracy: 0.001)
        XCTAssertEqualOptional(report.totalCost, 600, accuracy: 0.001)
        XCTAssertEqualOptional(report.kmPerGallon, 20, accuracy: 0.001)
        XCTAssertEqual(report.daysOfUse, 4)
        XCTAssertEqual(report.cycleCount, 1)
    }

    func testDetailedMonthlyReportsAggregateAcrossVehiclesWhenFilterIsNil() throws {
        let bmw = Vehicle(
            name: "Roadster",
            make: "BMW",
            modelName: "Z4",
            year: 2003,
            tankCapacityGallons: 14
        )
        let toyota = Vehicle(
            name: "Commuter",
            make: "Toyota",
            modelName: "Yaris",
            year: 2020,
            tankCapacityGallons: 16
        )
        let fills = [
            fill(vehicle: bmw, day: 1, odometer: 1_000, gallons: 10, total: 300),
            fill(vehicle: bmw, day: 10, odometer: 1_250, gallons: 10, total: 350),
            fill(vehicle: toyota, day: 2, odometer: 5_000, gallons: 18, total: 540),
            fill(vehicle: toyota, day: 14, odometer: 5_480, gallons: 20, total: 700),
        ]

        let report = try XCTUnwrap(
            AnalyticsEngine.detailedMonthlyReports(
                fills: fills,
                snapshots: [],
                adjustments: [],
                vehicleID: nil,
                mode: .finalFillMonth,
                calendar: calendar,
                now: date(day: 15)
            ).first
        )

        XCTAssertEqual(report.consumptionOrigin, .real)
        XCTAssertEqual(report.fillCount, 4)
        XCTAssertEqual(report.totalPaid, 1_890, accuracy: 0.001)
        XCTAssertEqual(report.distanceKilometers, 730, accuracy: 0.001)
        XCTAssertEqualOptional(report.gallonsConsumed, 30, accuracy: 0.001)
        XCTAssertEqualOptional(report.kmPerGallon, 730.0 / 30.0, accuracy: 0.001)
        XCTAssertEqualOptional(report.averageAutonomyKilometers, 367, accuracy: 0.001)
        XCTAssertEqualOptional(report.bestTank?.kmPerGallon, 25, accuracy: 0.001)
        XCTAssertEqualOptional(report.worstTank?.kmPerGallon, 24, accuracy: 0.001)
        XCTAssertEqual(report.cycleCount, 2)
    }

    func testDetailedMonthlyReportsBuildPastEstimatedMonthFromSnapshotOnlyActivity() throws {
        let vehicle = Vehicle(
            name: "Roadster",
            make: "BMW",
            modelName: "Z4",
            year: 2003,
            fuelEconomyReferenceKilometersPerGallon: 20
        )
        let snapshot = SnapshotEvent(
            date: date(month: 6, day: 22),
            vehicle: vehicle,
            odometerKilometers: 173_599.9,
            tripKilometers: 100,
            fuelLevelRemaining: 8
        )

        let report = try XCTUnwrap(
            AnalyticsEngine.detailedMonthlyReports(
                fills: [],
                snapshots: [snapshot],
                adjustments: [],
                vehicleID: vehicle.id,
                mode: .finalFillMonth,
                calendar: calendar,
                now: date(month: 7, day: 15)
            ).first
        )

        XCTAssertEqual(report.consumptionOrigin, .estimated)
        XCTAssertEqual(report.totalPaid, 0, accuracy: 0.001)
        XCTAssertEqual(report.distanceKilometers, 100, accuracy: 0.001)
        XCTAssertEqualOptional(report.gallonsConsumed, 5, accuracy: 0.001)
        XCTAssertEqualOptional(report.kmPerGallon, 20, accuracy: 0.001)
        XCTAssertNil(report.estimatedConsumedCost)
    }

    func testDetailedMonthlyReportsKeepPurchasesOnlyMonthVisibleEvenWithoutDistance() throws {
        let vehicle = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003)
        let fill = fill(vehicle: vehicle, day: 12, odometer: 1_000, gallons: 12.5, total: 412.75)

        let report = try XCTUnwrap(
            AnalyticsEngine.detailedMonthlyReports(
                fills: [fill],
                snapshots: [],
                adjustments: [],
                vehicleID: vehicle.id,
                mode: .finalFillMonth,
                calendar: calendar,
                now: date(day: 15)
            ).first
        )

        XCTAssertEqual(report.fillCount, 1)
        XCTAssertEqual(report.totalPaid, 412.75, accuracy: 0.001)
        XCTAssertEqual(report.distanceKilometers, 0, accuracy: 0.001)
        XCTAssertNil(report.gallonsConsumed)
        XCTAssertNil(report.costPerKilometer)
    }

    func testTankComparisonCSVRowsIncludeBestAndWorstLabels() {
        let comparisons = [
            TankComparisonReport(
                id: UUID(),
                vehicleID: UUID(),
                vehicleName: "Roadster BMW Z4 2003",
                startDate: date(day: 1),
                endDate: date(day: 10),
                openingOdometerKilometers: 1_000,
                closingOdometerKilometers: 1_250,
                distanceKilometers: 250,
                gallons: 10,
                totalCost: 350,
                kmPerGallon: 25,
                costPerKilometer: 1.4,
                isBest: true,
                isWorst: false
            ),
            TankComparisonReport(
                id: UUID(),
                vehicleID: UUID(),
                vehicleName: "Roadster BMW Z4 2003",
                startDate: date(day: 10),
                endDate: date(day: 20),
                openingOdometerKilometers: 1_250,
                closingOdometerKilometers: 1_450,
                distanceKilometers: 200,
                gallons: 12,
                totalCost: 420,
                kmPerGallon: 16.6667,
                costPerKilometer: 2.1,
                isBest: false,
                isWorst: true
            )
        ]

        let rows = AnalyticsEngine.tankComparisonCSVRows(comparisons)

        XCTAssertEqual(rows[0][0], "inicio")
        XCTAssertEqual(rows[1][9], "mejor")
        XCTAssertEqual(rows[2][9], "peor")
    }

    func testRefuelLocationsUseSavedCoordinatesAndSortNewestFirst() {
        let vehicle = Vehicle(name: "BMW", make: "BMW", modelName: "Z4", year: 2003)
        let first = FuelFillEvent(
            date: date(day: 6),
            vehicle: vehicle,
            odometerKilometers: 1_240,
            gallons: 12,
            pricePerGallon: 35,
            totalCost: 420,
            stationName: "Demo Station West",
            latitude: 37.3230,
            longitude: -122.0322
        )
        let second = FuelFillEvent(
            date: date(day: 12),
            vehicle: vehicle,
            odometerKilometers: 1_520,
            gallons: 11.3,
            pricePerGallon: 34.89,
            totalCost: 394.30,
            stationName: "Demo Station Archive",
            latitude: 37.3318,
            longitude: -122.0312
        )
        let withoutLocation = FuelFillEvent(
            date: date(day: 14),
            vehicle: vehicle,
            odometerKilometers: 1_700,
            gallons: 10,
            pricePerGallon: 35,
            totalCost: 350,
            stationName: "Sin coordenadas"
        )

        let points = AnalyticsEngine.refuelLocations(
            fills: [first, second, withoutLocation],
            vehicleID: vehicle.id
        )

        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].stationName, "Demo Station Archive")
        XCTAssertEqual(points[0].latitude, 37.3318, accuracy: 0.0001)
        XCTAssertEqual(points[0].longitude, -122.0312, accuracy: 0.0001)
        XCTAssertEqual(points[1].stationName, "Demo Station West")
    }

    private func fill(
        vehicle: Vehicle,
        month: Int = 6,
        day: Int,
        odometer: Double,
        gallons: Double,
        total: Double,
        isFullTank: Bool = true
    ) -> FuelFillEvent {
        FuelFillEvent(
            date: date(month: month, day: day),
            vehicle: vehicle,
            odometerKilometers: odometer,
            gallons: gallons,
            pricePerGallon: gallons > 0 ? total / gallons : 0,
            totalCost: total,
            isFullTank: isFullTank
        )
    }

    private func date(month: Int = 6, day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }
}
