import SwiftData
import UIKit
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

    func testResetServiceDeletesSelectedVehicleDataAndPreservesVehicles() throws {
        let context = try IntegrationTestSupport.makeInMemoryContext()
        let vehicle = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003)
        let otherVehicle = Vehicle(name: "Commuter", make: "Toyota", modelName: "Yaris", year: 2020)
        let fill = FuelFillEvent(vehicle: vehicle, odometerKilometers: 1_000, gallons: 10, pricePerGallon: 35, totalCost: 350)
        let snapshot = SnapshotEvent(vehicle: vehicle, odometerKilometers: 1_050, fuelLevelRemaining: 7)
        let adjustment = MonthlyManualAdjustment(monthStart: Date().startOfMonth(), vehicle: vehicle, manualDistanceKilometers: 10)
        let otherFill = FuelFillEvent(vehicle: otherVehicle, odometerKilometers: 2_000, gallons: 8, pricePerGallon: 34, totalCost: 272)
        let imagePath = try ImageStorageService.shared.saveImage(makeImage(color: .orange), preferredName: "reset-test-\(UUID().uuidString)")
        let asset = ImageAsset(eventID: fill.id, ownerType: .fillUp, kind: .invoice, localPath: imagePath)

        context.insert(vehicle)
        context.insert(otherVehicle)
        context.insert(fill)
        context.insert(snapshot)
        context.insert(adjustment)
        context.insert(otherFill)
        context.insert(asset)
        try context.save()

        XCTAssertTrue(FileManager.default.fileExists(atPath: imagePath))

        try ResetService.resetData(for: vehicle, context: context)

        XCTAssertEqual(try IntegrationTestSupport.count(Vehicle.self, in: context), 2)
        XCTAssertEqual(try IntegrationTestSupport.count(FuelFillEvent.self, in: context), 1)
        XCTAssertEqual(try IntegrationTestSupport.count(SnapshotEvent.self, in: context), 0)
        XCTAssertEqual(try IntegrationTestSupport.count(MonthlyManualAdjustment.self, in: context), 0)
        XCTAssertEqual(try IntegrationTestSupport.count(ImageAsset.self, in: context), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imagePath))

        let remainingFills = try context.fetch(FetchDescriptor<FuelFillEvent>())
        XCTAssertEqual(remainingFills.first?.vehicle?.id, otherVehicle.id)
    }

    private func makeImage(color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
