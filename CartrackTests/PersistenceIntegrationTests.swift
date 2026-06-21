import SwiftData
import XCTest
@testable import Cartrack

final class PersistenceIntegrationTests: XCTestCase {
    func testInMemoryContainerPersistsVehicleAndEventsInsideContext() throws {
        let context = try IntegrationTestSupport.makeInMemoryContext()
        let vehicle = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003)
        let fill = FuelFillEvent(
            date: Date(timeIntervalSince1970: 1_000),
            vehicle: vehicle,
            odometerKilometers: 1_000,
            gallons: 10.2500,
            pricePerGallon: 32.10,
            totalCost: 329.03,
            fuelLevelRemaining: 8
        )
        let snapshot = SnapshotEvent(
            date: Date(timeIntervalSince1970: 2_000),
            vehicle: vehicle,
            odometerKilometers: 1_100,
            fuelLevelRemaining: 6.5
        )
        let adjustment = MonthlyManualAdjustment(
            monthStart: Date(timeIntervalSince1970: 0).startOfMonth(),
            vehicle: vehicle,
            manualDistanceKilometers: 25
        )

        context.insert(vehicle)
        context.insert(fill)
        context.insert(snapshot)
        context.insert(adjustment)
        try context.save()

        XCTAssertEqual(try IntegrationTestSupport.count(Vehicle.self, in: context), 1)
        XCTAssertEqual(try IntegrationTestSupport.count(FuelFillEvent.self, in: context), 1)
        XCTAssertEqual(try IntegrationTestSupport.count(SnapshotEvent.self, in: context), 1)
        XCTAssertEqual(try IntegrationTestSupport.count(MonthlyManualAdjustment.self, in: context), 1)
    }

    func testResetServiceDeletesAllDomainDataAndImageAssets() throws {
        let context = try IntegrationTestSupport.makeInMemoryContext()
        let vehicle = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003)
        let fill = FuelFillEvent(vehicle: vehicle, odometerKilometers: 1_000, gallons: 10, pricePerGallon: 35, totalCost: 350)
        let snapshot = SnapshotEvent(vehicle: vehicle, odometerKilometers: 1_050, fuelLevelRemaining: 7)
        let adjustment = MonthlyManualAdjustment(monthStart: Date().startOfMonth(), vehicle: vehicle, manualDistanceKilometers: 10)
        let asset = ImageAsset(eventID: fill.id, ownerType: .fillUp, kind: .invoice, localPath: "/tmp/non-existent-cartrack-test.jpg")

        context.insert(vehicle)
        context.insert(fill)
        context.insert(snapshot)
        context.insert(adjustment)
        context.insert(asset)
        try context.save()

        try ResetService.resetAll(context: context)

        XCTAssertEqual(try IntegrationTestSupport.count(Vehicle.self, in: context), 0)
        XCTAssertEqual(try IntegrationTestSupport.count(FuelFillEvent.self, in: context), 0)
        XCTAssertEqual(try IntegrationTestSupport.count(SnapshotEvent.self, in: context), 0)
        XCTAssertEqual(try IntegrationTestSupport.count(MonthlyManualAdjustment.self, in: context), 0)
        XCTAssertEqual(try IntegrationTestSupport.count(ImageAsset.self, in: context), 0)
    }
}
