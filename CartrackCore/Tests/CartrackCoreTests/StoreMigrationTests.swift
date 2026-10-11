import Foundation
import SwiftData
import XCTest
@testable import CartrackCore

final class StoreMigrationTests: XCTestCase {
    func testFreshInstallCreatesVersionedStoreAndReopensWithoutDuplicates() throws {
        try withTemporaryDirectory { directory in
            let legacyURL = directory.appendingPathComponent("unused-v1.store")
            let first = try CartrackModelContainer.make(applicationSupportURL: directory,
                                                         legacyStoreURL: legacyURL)
            XCTAssertEqual(try ModelContext(first).fetch(FetchDescriptor<LocalStoreVersion>()).count, 1)

            let second = try CartrackModelContainer.make(applicationSupportURL: directory,
                                                          legacyStoreURL: legacyURL)
            XCTAssertEqual(try ModelContext(second).fetch(FetchDescriptor<LocalStoreVersion>()).count, 1)
            XCTAssertEqual(try ModelContext(second).fetch(FetchDescriptor<Vehicle>()).count, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        }
    }

    func testEmptyLegacyStoreMigratesWithoutCreatingRecords() throws {
        try withTemporaryDirectory { directory in
            let legacyURL = directory.appendingPathComponent("empty-v1.store")
            let legacy = try makeLegacyContainer(at: legacyURL)
            XCTAssertEqual(try ModelContext(legacy).fetch(FetchDescriptor<Vehicle>()).count, 0)

            let migrated = try CartrackModelContainer.make(applicationSupportURL: directory,
                                                            legacyStoreURL: legacyURL)
            XCTAssertEqual(try ModelContext(migrated).fetch(FetchDescriptor<LocalStoreVersion>()).count, 1)
            XCTAssertEqual(try ModelContext(migrated).fetch(FetchDescriptor<Vehicle>()).count, 0)
            XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        }
    }

    func testMissingLegacyImagePreservesReferenceWithoutInventingPhotoData() throws {
        try withTemporaryDirectory { directory in
            let legacyURL = directory.appendingPathComponent("v1.store")
            let absentPhotoURL = directory.appendingPathComponent("missing.jpg")
            let legacy = try makeLegacyContainer(at: legacyURL)
            let context = ModelContext(legacy)
            let vehicle = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003)
            let fill = FuelFillEvent(vehicle: vehicle, odometerKilometers: 100, gallons: 1,
                                     pricePerGallon: 40, totalCost: 40)
            context.insert(vehicle)
            context.insert(fill)
            context.insert(ImageAsset(eventID: fill.id, ownerType: .fillUp,
                                      kind: .invoice, localPath: absentPhotoURL.path))
            try context.save()

            let migrated = try CartrackModelContainer.make(applicationSupportURL: directory,
                                                            legacyStoreURL: legacyURL)
            XCTAssertEqual(try ModelContext(migrated).fetch(FetchDescriptor<ImageAsset>()).first?.localPath,
                           absentPhotoURL.path)
            XCTAssertFalse(FileManager.default.fileExists(atPath: absentPhotoURL.path))
        }
    }

    func testMigrationPreservesMultipleVehiclesEventsAdjustmentsAndLocalImages() throws {
        try withTemporaryDirectory { directory in
            let legacyURL = directory.appendingPathComponent("v1.store")
            let photoURL = directory.appendingPathComponent("local-evidence.jpg")
            try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: photoURL)
            let source = try makeLegacyContainer(at: legacyURL)
            let sourceContext = ModelContext(source)
            let bmw = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003,
                              odometerUnit: .miles, tankCapacityGallons: 14, fuelScaleMax: 8,
                              fuelScaleStep: 0.25, notes: "local-only")
            let toyota = Vehicle(name: "Commuter", make: "Toyota", modelName: "Yaris", year: 2020,
                                 odometerUnit: .kilometers)
            sourceContext.insert(bmw)
            sourceContext.insert(toyota)
            let fill = FuelFillEvent(vehicle: bmw, odometerMilesOriginal: 108_749,
                                     odometerKilometers: UnitConversion.milesToKilometers(108_749),
                                     tripMilesOriginal: 587.3,
                                     tripKilometers: UnitConversion.milesToKilometers(587.3),
                                     gallons: 11, pricePerGallon: 43, totalCost: 473,
                                     isFullTank: true, stationName: "Local station",
                                     fuelLevelRemaining: 8, invoiceOCRText: "legacy OCR")
            let snapshot = SnapshotEvent(vehicle: toyota, odometerKilometers: 10_000,
                                         tripKilometers: 80, fuelLevelRemaining: 4)
            let adjustment = MonthlyManualAdjustment(monthStart: Date(timeIntervalSince1970: 1_725_000_000),
                                                      vehicle: bmw, manualDistanceMiles: 5, note: "test")
            sourceContext.insert(fill)
            sourceContext.insert(snapshot)
            sourceContext.insert(adjustment)
            sourceContext.insert(ImageAsset(eventID: fill.id, ownerType: .fillUp, kind: .invoice,
                                            localPath: photoURL.path))
            try sourceContext.save()

            let migrated = try CartrackModelContainer.make(applicationSupportURL: directory,
                                                            legacyStoreURL: legacyURL)
            let context = ModelContext(migrated)
            XCTAssertEqual(try context.fetch(FetchDescriptor<Vehicle>()).count, 2)
            let savedFill = try XCTUnwrap(context.fetch(FetchDescriptor<FuelFillEvent>()).first)
            XCTAssertEqual(savedFill.id, fill.id)
            XCTAssertEqual(savedFill.vehicle?.id, bmw.id)
            XCTAssertEqual(savedFill.odometerKilometers, fill.odometerKilometers)
            XCTAssertEqual(savedFill.tripKilometers, fill.tripKilometers)
            XCTAssertEqual(savedFill.gallons, 11)
            XCTAssertEqual(savedFill.totalCost, 473)
            XCTAssertEqual(savedFill.invoiceOCRText, "legacy OCR")
            XCTAssertEqual(try context.fetch(FetchDescriptor<SnapshotEvent>()).first?.vehicle?.id, toyota.id)
            XCTAssertEqual(try context.fetch(FetchDescriptor<MonthlyManualAdjustment>()).first?.vehicle?.id, bmw.id)
            XCTAssertEqual(try context.fetch(FetchDescriptor<ImageAsset>()).first?.localPath, photoURL.path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: photoURL.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
            XCTAssertEqual(try context.fetch(FetchDescriptor<LocalStoreVersion>()).first?.schemaVersion, 2)
            XCTAssertEqual(try context.fetch(FetchDescriptor<SyncMetadataRecord>()).count, 4)
            let legacyEvidence = try context.fetch(FetchDescriptor<OCRFieldEvidence>())
            XCTAssertEqual(Set(legacyEvidence.map(\.fieldRawValue)), ["amount", "price", "volume"])
            XCTAssertTrue(legacyEvidence.allSatisfy { $0.rawText == nil && $0.algorithmVersion == "legacy-v1" })

            let backupDirectory = directory.appendingPathComponent("CartrackV2/Backups")
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backupDirectory.path)
                .filter { $0.hasSuffix(".sqlite") }.count, 1)

            let reopened = try CartrackModelContainer.make(applicationSupportURL: directory,
                                                            legacyStoreURL: legacyURL)
            XCTAssertEqual(try ModelContext(reopened).fetch(FetchDescriptor<FuelFillEvent>()).count, 1)
            XCTAssertEqual(try ModelContext(reopened).fetch(FetchDescriptor<ImageAsset>()).count, 1)
        }
    }

    func testInjectedFailuresKeepV1UsableAndDoNotActivatePartialStore() throws {
        for checkpoint in StoreMigrationCheckpoint.allCases {
            try withTemporaryDirectory { directory in
                let legacyURL = directory.appendingPathComponent("v1.store")
                let legacy = try makeLegacyContainer(at: legacyURL)
                let context = ModelContext(legacy)
                let vehicle = Vehicle(name: "Original", make: "BMW", modelName: "Z4", year: 2003)
                context.insert(vehicle)
                try context.save()

                XCTAssertThrowsError(try CartrackModelContainer.make(
                    applicationSupportURL: directory, legacyStoreURL: legacyURL, failureAt: checkpoint
                )) { error in
                    guard case StoreMigrationError.injected(let actual) = error else {
                        return XCTFail("Unexpected error: \(error)")
                    }
                    XCTAssertEqual(actual, checkpoint)
                }
                XCTAssertFalse(FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent("CartrackV2/active-store.json").path
                ))
                XCTAssertEqual(try ModelContext(legacy).fetch(FetchDescriptor<Vehicle>()).first?.id, vehicle.id)
                let recovered = try CartrackModelContainer.make(applicationSupportURL: directory,
                                                                 legacyStoreURL: legacyURL)
                XCTAssertEqual(try ModelContext(recovered).fetch(FetchDescriptor<Vehicle>()).first?.id, vehicle.id)
            }
        }
    }

    private func makeLegacyContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema(CartrackV1Schema.models)
        let configuration = ModelConfiguration("CartrackData", schema: schema, url: url, allowsSave: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CartrackMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
