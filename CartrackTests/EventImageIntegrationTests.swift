import SwiftData
import UIKit
import XCTest
@testable import Cartrack

final class EventImageIntegrationTests: XCTestCase {
    func testEventImageSynchronizerCreatesReplacesAndRemovesAssets() throws {
        let context = try IntegrationTestSupport.makeInMemoryContext()
        let vehicle = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003)
        let fill = FuelFillEvent(vehicle: vehicle, odometerKilometers: 1_000, gallons: 10, pricePerGallon: 35, totalCost: 350)
        context.insert(vehicle)
        context.insert(fill)
        try context.save()

        try EventImageSynchronizer.replaceAssets(
            for: fill,
            images: [.invoice: makeImage(color: .red)],
            context: context
        )
        try context.save()

        var assets = try context.fetch(FetchDescriptor<ImageAsset>())
        XCTAssertEqual(assets.count, 1)
        let firstPath = try XCTUnwrap(assets.first?.localPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstPath))

        try EventImageSynchronizer.replaceAssets(
            for: fill,
            images: [.invoice: makeImage(color: .blue)],
            context: context
        )
        try context.save()

        assets = try context.fetch(FetchDescriptor<ImageAsset>())
        XCTAssertEqual(assets.count, 1)
        let secondPath = try XCTUnwrap(assets.first?.localPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstPath))

        try EventImageSynchronizer.replaceAssets(
            for: fill,
            images: [:],
            removedKinds: [.invoice],
            context: context
        )
        try context.save()

        XCTAssertEqual(try IntegrationTestSupport.count(ImageAsset.self, in: context), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondPath))
    }

    func testEventDeletionServiceDeletesSnapshotAndOwnedImages() throws {
        let context = try IntegrationTestSupport.makeInMemoryContext()
        let vehicle = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003)
        let snapshot = SnapshotEvent(vehicle: vehicle, odometerKilometers: 1_050, fuelLevelRemaining: 7)
        context.insert(vehicle)
        context.insert(snapshot)
        try context.save()

        try EventImageSynchronizer.replaceAssets(
            for: snapshot,
            images: [.fuelLevel: makeImage(color: .green)],
            context: context
        )
        try context.save()

        let path = try XCTUnwrap(try context.fetch(FetchDescriptor<ImageAsset>()).first?.localPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        try EventDeletionService.delete(snapshotEvent: snapshot, context: context)

        XCTAssertEqual(try IntegrationTestSupport.count(SnapshotEvent.self, in: context), 0)
        XCTAssertEqual(try IntegrationTestSupport.count(ImageAsset.self, in: context), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testVehicleDeletionDeletesOwnedEventsAdjustmentsAndImages() throws {
        let context = try IntegrationTestSupport.makeInMemoryContext()
        let vehicle = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003)
        let fill = FuelFillEvent(vehicle: vehicle, odometerKilometers: 1_000, gallons: 10, pricePerGallon: 35, totalCost: 350)
        let snapshot = SnapshotEvent(vehicle: vehicle, odometerKilometers: 1_050, fuelLevelRemaining: 7)
        let adjustment = MonthlyManualAdjustment(monthStart: Date().startOfMonth(), vehicle: vehicle, manualDistanceKilometers: 25)

        context.insert(vehicle)
        context.insert(fill)
        context.insert(snapshot)
        context.insert(adjustment)
        try context.save()

        try EventImageSynchronizer.replaceAssets(
            for: fill,
            images: [.invoice: makeImage(color: .red)],
            context: context
        )
        try EventImageSynchronizer.replaceAssets(
            for: snapshot,
            images: [.fuelLevel: makeImage(color: .green)],
            context: context
        )
        try context.save()

        let paths = try context.fetch(FetchDescriptor<ImageAsset>()).map(\.localPath)
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths.allSatisfy { FileManager.default.fileExists(atPath: $0) })

        try EventDeletionService.delete(vehicle: vehicle, context: context)

        XCTAssertEqual(try IntegrationTestSupport.count(Vehicle.self, in: context), 0)
        XCTAssertEqual(try IntegrationTestSupport.count(FuelFillEvent.self, in: context), 0)
        XCTAssertEqual(try IntegrationTestSupport.count(SnapshotEvent.self, in: context), 0)
        XCTAssertEqual(try IntegrationTestSupport.count(MonthlyManualAdjustment.self, in: context), 0)
        XCTAssertEqual(try IntegrationTestSupport.count(ImageAsset.self, in: context), 0)
        XCTAssertTrue(paths.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
    }

    private func makeImage(color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
