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

    func testVehiclePersistsExtendedConfigurationFields() throws {
        let context = try IntegrationTestSupport.makeInMemoryContext()
        let vehicle = Vehicle(
            name: "Roadster",
            make: "BMW",
            modelName: "Z4",
            year: 2003,
            engine: "2.5i",
            plate: "P123ABC",
            odometerUnit: .kilometers,
            tankCapacityGallons: 16,
            fuelScaleMax: 10,
            fuelScaleStep: 0.5,
            fuelEconomyReferenceKilometersPerGallon: 30,
            notes: "Configuracion personalizada"
        )

        context.insert(vehicle)
        try context.save()

        let savedVehicles = try context.fetch(FetchDescriptor<Vehicle>())
        XCTAssertEqual(savedVehicles.count, 1)

        let savedVehicle = try XCTUnwrap(savedVehicles.first)
        XCTAssertEqual(savedVehicle.engine, "2.5i")
        XCTAssertEqual(savedVehicle.plate, "P123ABC")
        XCTAssertEqual(savedVehicle.odometerUnit, .kilometers)
        XCTAssertEqual(savedVehicle.tankCapacityGallons, 16, accuracy: 0.001)
        XCTAssertEqual(savedVehicle.fuelScaleMax, 10, accuracy: 0.001)
        XCTAssertEqual(savedVehicle.fuelScaleStep, 0.5, accuracy: 0.001)
        XCTAssertEqual(savedVehicle.fuelEconomyReferenceKilometersPerGallon, 30, accuracy: 0.001)
        XCTAssertEqual(savedVehicle.notes, "Configuracion personalizada")
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

    func testReportExportServiceBuildsCSVWithWeeklyRows() throws {
        let payload = ReportExportPayload(
            vehicleName: "Roadster BMW Z4 2003",
            generatedAt: Date(timeIntervalSince1970: 1_000),
            granularity: .weekly,
            weeklyReports: [
                DetailedWeeklyReport(
                    id: Date(timeIntervalSince1970: 0),
                    weekStart: Date(timeIntervalSince1970: 0),
                    vehicleID: UUID(),
                    distanceKilometers: 117.5,
                    gallons: 4.7959,
                    totalCost: 190.63,
                    kmPerGallon: 24.5,
                    daysOfUse: 2,
                    averageDailyKilometers: 58.75,
                    cycleCount: 0,
                    valueOrigin: .estimated
                )
            ],
            monthlyReports: [],
            tankComparisons: []
        )

        let url = try ReportExportService.exportCSV(payload: payload)
        let contents = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(contents.contains("reporte,Semanal"))
        XCTAssertTrue(contents.contains("semana_inicio"))
        XCTAssertTrue(contents.contains("estimated"))
        XCTAssertTrue(contents.contains("117.5000"))
    }

    func testReportExportServiceBuildsPDFFile() throws {
        let payload = ReportExportPayload(
            vehicleName: "Roadster BMW Z4 2003",
            generatedAt: Date(timeIntervalSince1970: 1_000),
            granularity: .monthly,
            weeklyReports: [],
            monthlyReports: [
                DetailedMonthlyReport(
                    id: Date(timeIntervalSince1970: 0),
                    monthStart: Date(timeIntervalSince1970: 0),
                    vehicleID: UUID(),
                    fillCount: 2,
                    totalPaid: 650,
                    distanceKilometers: 330,
                    gallonsConsumed: 13.2,
                    consumptionOrigin: .mixed,
                    costPerKilometer: 1.9696,
                    averageAutonomyKilometers: 350,
                    bestTank: nil,
                    worstTank: nil,
                    estimatedConsumedCost: 429,
                    paidVsConsumedDelta: 221,
                    cycleCount: 1,
                    daysOfUse: 3,
                    averageDailyKilometers: 110
                )
            ],
            tankComparisons: []
        )

        let url = try ReportExportService.exportPDF(payload: payload)
        let data = try Data(contentsOf: url)
        let header = String(decoding: data.prefix(4), as: UTF8.self)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertGreaterThan(data.count, 100)
        XCTAssertEqual(header, "%PDF")
    }

    func testBackupTransferServiceRoundTripsDataAndImages() throws {
        let sourceContext = try IntegrationTestSupport.makeInMemoryContext()
        let vehicle = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003, plate: "P123ABC")
        let fill = FuelFillEvent(
            date: Date(timeIntervalSince1970: 1_000),
            vehicle: vehicle,
            odometerMilesOriginal: 107_381,
            odometerKilometers: UnitConversion.milesToKilometers(107_381),
            gallons: 11.3468,
            pricePerGallon: 34.75,
            totalCost: 394.30,
            stationName: "Demo Station Archive",
            fuelLevelRemaining: 8,
            latitude: 37.3318,
            longitude: -122.0312
        )
        let snapshot = SnapshotEvent(
            date: Date(timeIntervalSince1970: 2_000),
            vehicle: vehicle,
            odometerMilesOriginal: 107_399,
            odometerKilometers: UnitConversion.milesToKilometers(107_399),
            tripMilesOriginal: 18,
            tripKilometers: UnitConversion.milesToKilometers(18),
            fuelLevelRemaining: 6.5,
            latitude: 37.3326,
            longitude: -122.0301
        )
        let adjustment = MonthlyManualAdjustment(
            monthStart: Date(timeIntervalSince1970: 0).startOfMonth(),
            vehicle: vehicle,
            manualDistanceKilometers: 25
        )
        let imagePath = try ImageStorageService.shared.saveImage(makeImage(color: .purple), preferredName: "backup-test-\(UUID().uuidString)")
        let asset = ImageAsset(eventID: fill.id, ownerType: .fillUp, kind: .invoice, localPath: imagePath)

        sourceContext.insert(vehicle)
        sourceContext.insert(fill)
        sourceContext.insert(snapshot)
        sourceContext.insert(adjustment)
        sourceContext.insert(asset)
        try sourceContext.save()

        let backupURL = try BackupTransferService.exportBackup(from: sourceContext)
        let destinationContext = try IntegrationTestSupport.makeInMemoryContext()
        let summary = try BackupTransferService.importBackup(from: backupURL, into: destinationContext)

        XCTAssertEqual(summary.vehicleCount, 1)
        XCTAssertEqual(summary.fillCount, 1)
        XCTAssertEqual(summary.snapshotCount, 1)
        XCTAssertEqual(summary.adjustmentCount, 1)
        XCTAssertEqual(summary.imageCount, 1)

        XCTAssertEqual(try IntegrationTestSupport.count(Vehicle.self, in: destinationContext), 1)
        XCTAssertEqual(try IntegrationTestSupport.count(FuelFillEvent.self, in: destinationContext), 1)
        XCTAssertEqual(try IntegrationTestSupport.count(SnapshotEvent.self, in: destinationContext), 1)
        XCTAssertEqual(try IntegrationTestSupport.count(MonthlyManualAdjustment.self, in: destinationContext), 1)
        XCTAssertEqual(try IntegrationTestSupport.count(ImageAsset.self, in: destinationContext), 1)

        let importedFill = try XCTUnwrap(try destinationContext.fetch(FetchDescriptor<FuelFillEvent>()).first)
        XCTAssertEqual(importedFill.stationName, "Demo Station Archive")
        XCTAssertEqual(try XCTUnwrap(importedFill.latitude), 37.3318, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(importedFill.longitude), -122.0312, accuracy: 0.0001)

        let importedAsset = try XCTUnwrap(try destinationContext.fetch(FetchDescriptor<ImageAsset>()).first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedAsset.localPath))
        XCTAssertNotNil(ImageStorageService.shared.loadImageData(at: importedAsset.localPath))
    }

    func testBackupTransferServiceImportReplacesExistingLocalData() throws {
        let sourceContext = try IntegrationTestSupport.makeInMemoryContext()
        let sourceVehicle = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003)
        sourceContext.insert(sourceVehicle)
        sourceContext.insert(FuelFillEvent(vehicle: sourceVehicle, odometerKilometers: 1_000, gallons: 10, pricePerGallon: 35, totalCost: 350))
        try sourceContext.save()

        let backupURL = try BackupTransferService.exportBackup(from: sourceContext)

        let destinationContext = try IntegrationTestSupport.makeInMemoryContext()
        let existingVehicle = Vehicle(name: "Commuter", make: "Toyota", modelName: "Yaris", year: 2020)
        let existingImagePath = try ImageStorageService.shared.saveImage(makeImage(color: .orange), preferredName: "backup-replace-\(UUID().uuidString)")
        destinationContext.insert(existingVehicle)
        destinationContext.insert(ImageAsset(eventID: UUID(), ownerType: .fillUp, kind: .invoice, localPath: existingImagePath))
        try destinationContext.save()

        XCTAssertTrue(FileManager.default.fileExists(atPath: existingImagePath))

        _ = try BackupTransferService.importBackup(from: backupURL, into: destinationContext)

        let vehicles = try destinationContext.fetch(FetchDescriptor<Vehicle>())
        XCTAssertEqual(vehicles.count, 1)
        XCTAssertEqual(vehicles.first?.displayName, "Roadster BMW Z4 2003")
        XCTAssertFalse(FileManager.default.fileExists(atPath: existingImagePath))
    }

    private func makeImage(color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
