import SwiftData
import UIKit
import XCTest
import CryptoKit
@testable import Cartrack

final class PersistenceIntegrationTests: XCTestCase {
    func testSyncMetadataMaintainerTracksBaselineSavesAndDeletion() throws {
        let context = try IntegrationTestSupport.makeInMemoryContext()
        let vehicle = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003)
        let fill = FuelFillEvent(vehicle: vehicle, odometerKilometers: 1_000,
                                 gallons: 10, pricePerGallon: 40, totalCost: 400)
        context.insert(vehicle)
        context.insert(fill)
        try SyncMetadataMaintainer.recordChange(ownerID: vehicle.id, kind: "vehicle",
                                                createdAt: vehicle.createdAt, updatedAt: vehicle.createdAt,
                                                in: context)
        try SyncMetadataMaintainer.recordChange(ownerID: fill.id, kind: "fuelEntry",
                                                createdAt: fill.createdAt, updatedAt: fill.updatedAt,
                                                in: context)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncMetadataRecord>()).count, 2)

        fill.notes = "edited"
        fill.updatedAt = .now
        try SyncMetadataMaintainer.recordChange(ownerID: fill.id, kind: "fuelEntry",
                                                createdAt: fill.createdAt, updatedAt: fill.updatedAt,
                                                in: context)
        try context.save()
        let fillMetadata = try context.fetch(FetchDescriptor<SyncMetadataRecord>())
            .first { $0.ownerID == fill.id }
        XCTAssertEqual(fillMetadata?.revision, 2)

        try EventDeletionService.delete(fillEvent: fill, context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncMetadataRecord>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncMetadataRecord>()).first?.ownerID,
                       vehicle.id)
    }

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
            tankComparisons: [],
            distanceUnit: .miles
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
            tankComparisons: [],
            distanceUnit: .miles
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

    func testVersion2BackupHasVerifiedManifestAndCanOmitImages() throws {
        let sourceContext = try IntegrationTestSupport.makeInMemoryContext()
        let vehicle = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003)
        let fill = FuelFillEvent(vehicle: vehicle, odometerKilometers: 1_000,
                                 gallons: 10, pricePerGallon: 35, totalCost: 350)
        let imagePath = try ImageStorageService.shared.saveImage(
            makeImage(color: .purple), preferredName: "backup-v2-\(UUID().uuidString)"
        )
        sourceContext.insert(vehicle)
        sourceContext.insert(fill)
        sourceContext.insert(ImageAsset(eventID: fill.id, ownerType: .fillUp,
                                        kind: .invoice, localPath: imagePath))
        try sourceContext.save()

        let fullPackage = try BackupTransferService.exportBackup(from: sourceContext, includeImages: true)
        XCTAssertEqual(fullPackage.pathExtension, "cartrackbackup")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fullPackage.appendingPathComponent("manifest.json").path
        ))
        let fullPlan = try BackupTransferService.inspectBackup(from: fullPackage)
        XCTAssertEqual(fullPlan.formatVersion, 2)
        XCTAssertEqual(fullPlan.schemaVersion, 2)
        XCTAssertTrue(fullPlan.includesImageBytes)
        XCTAssertEqual(fullPlan.imageCount, 1)

        let structuredOnly = try BackupTransferService.exportBackup(from: sourceContext, includeImages: false)
        let structuredPlan = try BackupTransferService.inspectBackup(from: structuredOnly)
        XCTAssertEqual(structuredPlan.formatVersion, 2)
        XCTAssertFalse(structuredPlan.includesImageBytes)
        XCTAssertEqual(structuredPlan.imageCount, 1)
        let records = try String(contentsOf: structuredOnly.appendingPathComponent("records.json"), encoding: .utf8)
        XCTAssertFalse(records.contains(imagePath))
        XCTAssertTrue(records.contains("\"hasLocalEvidence\" : true"))

        let destination = try IntegrationTestSupport.makeInMemoryContext()
        let summary = try BackupTransferService.importBackup(from: structuredOnly, into: destination)
        XCTAssertEqual(summary.imageCount, 1)
        XCTAssertEqual(try IntegrationTestSupport.count(ImageAsset.self, in: destination), 0)
    }

    func testVersion2BackupRestoresConfirmedCaptureEvidenceWithoutAbsolutePaths() throws {
        let source = try IntegrationTestSupport.makeInMemoryContext()
        let vehicle = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003)
        let fill = FuelFillEvent(vehicle: vehicle, odometerKilometers: 1_000,
                                 gallons: 10, pricePerGallon: 35, totalCost: 350)
        let sessionID = UUID()
        let stored = try CapturePhotoStore().save(makeImage(color: .purple), sessionID: sessionID,
                                                   kind: .odometer)
        source.insert(vehicle)
        source.insert(fill)
        source.insert(LocalPhotoAsset(
            id: stored.id, sessionID: sessionID, eventID: fill.id, kindRawValue: stored.kind,
            localRelativePath: stored.localRelativePath, sha256: stored.sha256,
            pixelWidth: stored.pixelWidth, pixelHeight: stored.pixelHeight,
            byteCount: stored.byteCount, mimeType: stored.mimeType, capturedAt: stored.capturedAt,
            optimizationStateRawValue: "optimized", createdAt: stored.createdAt
        ))
        try source.save()

        let package = try BackupTransferService.exportBackup(from: source, includeImages: true)
        let records = try String(contentsOf: package.appendingPathComponent("records.json"), encoding: .utf8)
        XCTAssertFalse(records.contains(stored.localRelativePath))
        XCTAssertEqual(try BackupTransferService.inspectBackup(from: package).imageCount, 1)

        let destination = try IntegrationTestSupport.makeInMemoryContext()
        _ = try BackupTransferService.importBackup(from: package, into: destination)
        let restored = try XCTUnwrap(destination.fetch(FetchDescriptor<LocalPhotoAsset>()).first)
        XCTAssertEqual(restored.id, stored.id)
        XCTAssertEqual(restored.sha256, stored.sha256)
        let restoredRecord = LocalPhotoRecord(
            id: restored.id, sessionID: restored.sessionID, eventID: restored.eventID,
            kind: restored.kindRawValue, localRelativePath: restored.localRelativePath,
            sha256: restored.sha256, pixelWidth: restored.pixelWidth,
            pixelHeight: restored.pixelHeight, byteCount: restored.byteCount,
            mimeType: restored.mimeType, capturedAt: restored.capturedAt,
            optimizationState: restored.optimizationStateRawValue, createdAt: restored.createdAt
        )
        XCTAssertNotNil(try CapturePhotoStore().load(restoredRecord))
    }

    func testBackupImportSupportsVersion1AndRejectsDuplicateUUIDs() throws {
        let source = try IntegrationTestSupport.makeInMemoryContext()
        let vehicle = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003)
        source.insert(vehicle)
        source.insert(FuelFillEvent(vehicle: vehicle, odometerKilometers: 1_000,
                                    gallons: 10, pricePerGallon: 35, totalCost: 350))
        try source.save()

        let package = try BackupTransferService.exportBackup(from: source, includeImages: false)
        var v1Object = try backupRecordsObject(in: package)
        v1Object["formatVersion"] = 1
        let v1URL = try writeBackupJSON(v1Object, named: "backup-v1")

        let destination = try IntegrationTestSupport.makeInMemoryContext()
        let v1Summary = try BackupTransferService.importBackup(from: v1URL, into: destination)
        XCTAssertEqual(v1Summary.vehicleCount, 1)
        XCTAssertEqual(v1Summary.fillCount, 1)

        var duplicateObject = v1Object
        var vehicles = try XCTUnwrap(duplicateObject["vehicles"] as? [[String: Any]])
        vehicles.append(try XCTUnwrap(vehicles.first))
        duplicateObject["vehicles"] = vehicles
        let duplicateURL = try writeBackupJSON(duplicateObject, named: "backup-duplicate")
        XCTAssertThrowsError(try BackupTransferService.inspectBackup(from: duplicateURL)) { error in
            guard case BackupTransferError.duplicateRecord = error else {
                return XCTFail("Expected duplicate backup rejection, got \(error)")
            }
        }
    }

    func testCorruptOrInterruptedImportPreservesExistingData() throws {
        let source = try IntegrationTestSupport.makeInMemoryContext()
        let importedVehicle = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003)
        source.insert(importedVehicle)
        source.insert(FuelFillEvent(vehicle: importedVehicle, odometerKilometers: 1_000,
                                    gallons: 10, pricePerGallon: 35, totalCost: 350))
        try source.save()
        let package = try BackupTransferService.exportBackup(from: source, includeImages: false)

        let destination = try IntegrationTestSupport.makeInMemoryContext()
        let originalVehicle = Vehicle(name: "Commuter", make: "Toyota", modelName: "Yaris", year: 2020)
        destination.insert(originalVehicle)
        try destination.save()

        let recordsURL = package.appendingPathComponent("records.json")
        let originalRecords = try Data(contentsOf: recordsURL)
        try (originalRecords + Data(" ".utf8)).write(to: recordsURL, options: .atomic)
        XCTAssertThrowsError(try BackupTransferService.importBackup(from: package, into: destination)) { error in
            guard case BackupTransferError.integrityFailed = error else {
                return XCTFail("Expected manifest integrity rejection, got \(error)")
            }
        }
        XCTAssertEqual(try IntegrationTestSupport.count(Vehicle.self, in: destination), 1)
        XCTAssertEqual(try XCTUnwrap(destination.fetch(FetchDescriptor<Vehicle>()).first).name, "Commuter")

        try originalRecords.write(to: recordsURL, options: .atomic)
        try rewriteManifestHash(for: recordsURL, in: package)
        XCTAssertThrowsError(
            try BackupTransferService.importBackup(from: package, into: destination,
                                                   failureAt: .beforeConfirmation)
        ) { error in
            guard case BackupTransferError.restoreInterrupted = error else {
                return XCTFail("Expected injected interruption, got \(error)")
            }
        }
        XCTAssertEqual(try IntegrationTestSupport.count(Vehicle.self, in: destination), 1)
        XCTAssertEqual(try XCTUnwrap(destination.fetch(FetchDescriptor<Vehicle>()).first).name, "Commuter")
    }

    private func backupRecordsObject(in package: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: package.appendingPathComponent("records.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func writeBackupJSON(_ object: [String: Any], named: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(named)-\(UUID().uuidString).cartrackbackup.json")
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url, options: .atomic)
        return url
    }

    private func rewriteManifestHash(for recordsURL: URL, in package: URL) throws {
        let manifestURL = package.appendingPathComponent("manifest.json")
        var manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        var files = try XCTUnwrap(manifest["files"] as? [[String: Any]])
        let records = try Data(contentsOf: recordsURL)
        let digest = SHA256.hash(data: records).map { String(format: "%02x", $0) }.joined()
        let index = try XCTUnwrap(files.firstIndex { $0["path"] as? String == "records.json" })
        files[index]["sha256"] = digest
        files[index]["byteCount"] = records.count
        manifest["files"] = files
        manifest["expectedTotalByteCount"] = files.reduce(0) { total, file in
            total + (file["byteCount"] as? Int ?? 0)
        }
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: manifestURL, options: .atomic)
    }

    private func makeImage(color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
