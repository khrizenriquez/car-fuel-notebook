import Foundation
import SwiftData
import XCTest
@testable import CartrackCore

@MainActor
final class V2RepositoryTests: XCTestCase {
    func testVehicleRepositoryRoundTripRevisionAndConflict() async throws {
        let container = try CartrackModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        let repository = SwiftDataVehicleRepository(context: context)
        var record = vehicle(name: "Roadster")

        try await repository.save(record)
        let insertedResult = try await repository.find(id: record.id)
        let inserted = try XCTUnwrap(insertedResult)
        XCTAssertEqual(inserted.name, "Roadster")
        XCTAssertEqual(inserted.reserveThresholdRatio, Decimal(string: "0.10"))
        XCTAssertEqual(inserted.sync.revision, 1)

        record.name = "Z4"
        try await repository.save(record)
        let updatedResult = try await repository.find(id: record.id)
        let updated = try XCTUnwrap(updatedResult)
        XCTAssertEqual(updated.name, "Z4")
        XCTAssertEqual(updated.sync.revision, 2)
        do {
            try await repository.save(record)
            XCTFail("A stale revision must not overwrite a newer record")
        } catch RepositoryError.conflict {
            let stillStored = try await repository.find(id: record.id)
            XCTAssertEqual(stillStored?.name, "Z4")
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<Vehicle>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncMetadataRecord>()).count, 1)
    }

    func testFuelAndSnapshotRepositoriesKeepVehiclesSeparatedAndFinancialDecimals() async throws {
        let container = try CartrackModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        let vehicles = SwiftDataVehicleRepository(context: context)
        let fills = SwiftDataFuelEntryRepository(context: context)
        let snapshots = SwiftDataUsageSnapshotRepository(context: context)
        let bmw = vehicle(name: "BMW")
        let toyota = vehicle(name: "Toyota")
        try await vehicles.save(bmw)
        try await vehicles.save(toyota)

        let sessionID = UUID()
        let fill = FuelEntryRecord(
            id: UUID(), vehicleID: bmw.id, occurredAt: .now,
            odometerKilometers: 175_000, tripKilometers: Decimal(string: "945.1"),
            volumeGallons: 11, unitPrice: 43, totalCost: 473, currencyCode: "GTQ",
            isFullTank: true, fuelLevelRemaining: 8, stationName: "Station",
            latitude: nil, longitude: nil, notes: "", sourceSessionID: sessionID,
            sync: metadata()
        )
        try await fills.save(fill)
        let savedFillResult = try await fills.find(id: fill.id)
        let savedFill = try XCTUnwrap(savedFillResult)
        XCTAssertEqual(savedFill.vehicleID, bmw.id)
        XCTAssertEqual(savedFill.tripKilometers, Decimal(string: "945.1"))
        XCTAssertEqual(savedFill.totalCost, 473)
        XCTAssertEqual(savedFill.currencyCode, "GTQ")
        XCTAssertEqual(savedFill.sourceSessionID, sessionID)
        let toyotaFills = try await fills.all(vehicleID: toyota.id)
        XCTAssertEqual(toyotaFills.count, 0)

        let snapshot = UsageSnapshotRecord(id: UUID(), vehicleID: toyota.id,
                                           occurredAt: .now, odometerKilometers: 50_000,
                                           tripKilometers: 30, fuelLevelRemaining: 4,
                                           latitude: nil, longitude: nil, notes: "usage",
                                           sourceSessionID: nil, sync: metadata())
        try await snapshots.save(snapshot)
        let toyotaSnapshots = try await snapshots.all(vehicleID: toyota.id)
        let bmwSnapshots = try await snapshots.all(vehicleID: bmw.id)
        XCTAssertEqual(toyotaSnapshots.count, 1)
        XCTAssertEqual(bmwSnapshots.count, 0)

        var orphan = fill
        orphan.id = UUID()
        orphan.vehicleID = UUID()
        do {
            try await fills.save(orphan)
            XCTFail("An event cannot belong to a missing vehicle")
        } catch RepositoryError.notFound {
            XCTAssertEqual(try context.fetch(FetchDescriptor<FuelFillEvent>()).count, 1)
        }
    }

    func testPhotoAndOCREvidenceStayLocalAndValidateInputs() async throws {
        let container = try CartrackModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        let photos = SwiftDataPhotoAssetRepository(context: context)
        let evidence = SwiftDataOCRFieldEvidenceRepository(context: context)
        let sessionID = UUID()
        let photo = LocalPhotoRecord(id: UUID(), sessionID: sessionID, eventID: nil,
                                     kind: "odometer", localRelativePath: "Photos/dashboard.jpg",
                                     sha256: String(repeating: "a", count: 64),
                                     pixelWidth: 1200, pixelHeight: 900, byteCount: 80_000,
                                     mimeType: "image/jpeg", capturedAt: .now,
                                     optimizationState: "original", createdAt: .now)
        try await photos.save(photo)
        let savedPhotos = try await photos.all(sessionID: sessionID)
        XCTAssertEqual(savedPhotos, [photo])

        let field = OCRFieldRecord(id: UUID(), sessionID: sessionID, ownerEventID: nil,
                                   field: "odometer", rawText: "108796",
                                   normalizedValue: "108796", unit: "mi", confidence: 0.82,
                                   confidenceBand: "high", sourcePhotoID: photo.id,
                                   validationCodes: [], wasManuallyCorrected: false,
                                   algorithmVersion: "v2-test")
        try await evidence.save(field)
        let savedEvidence = try await evidence.all(sessionID: sessionID)
        XCTAssertEqual(savedEvidence, [field])

        var escapingPhoto = photo
        escapingPhoto.id = UUID()
        escapingPhoto.localRelativePath = "../private.jpg"
        do {
            try await photos.save(escapingPhoto)
            XCTFail("A local relative path must not escape its root")
        } catch RepositoryError.invalidRecord("photo.pathOrSize.invalid") {
            XCTAssertEqual(try context.fetch(FetchDescriptor<LocalPhotoAsset>()).count, 1)
        }

        var invalidHashPhoto = photo
        invalidHashPhoto.id = UUID()
        invalidHashPhoto.sha256 = "not-a-hash"
        do {
            try await photos.save(invalidHashPhoto)
            XCTFail("A photo reference needs a valid local SHA-256")
        } catch RepositoryError.invalidRecord("photo.pathOrSize.invalid") {
            XCTAssertEqual(try context.fetch(FetchDescriptor<LocalPhotoAsset>()).count, 1)
        }

        var invalidEvidence = field
        invalidEvidence.id = UUID()
        invalidEvidence.confidence = 2
        do {
            try await evidence.save(invalidEvidence)
            XCTFail("Confidence must be within 0...1")
        } catch RepositoryError.invalidRecord("ocr.evidence.invalid") {
            XCTAssertEqual(try context.fetch(FetchDescriptor<OCRFieldEvidence>()).count, 1)
        }
    }

    func testExistingT05V2StoreAddsModelsAndMetadataWithoutDuplicatingRecords() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CartrackV2UpgradeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storesDirectory = directory.appendingPathComponent("CartrackV2/Stores", isDirectory: true)
        try FileManager.default.createDirectory(at: storesDirectory, withIntermediateDirectories: true)
        let storeName = "\(UUID().uuidString).store"
        let storeURL = storesDirectory.appendingPathComponent(storeName)
        let oldSchema = Schema(CartrackV1Schema.models + [LocalStoreVersion.self],
                               version: Schema.Version(2, 0, 0))
        let oldConfiguration = ModelConfiguration("CartrackDataV2", schema: oldSchema,
                                                   url: storeURL, allowsSave: true,
                                                   cloudKitDatabase: .none)
        let oldContainer = try ModelContainer(for: oldSchema, configurations: [oldConfiguration])
        let oldContext = ModelContext(oldContainer)
        let vehicle = Vehicle(name: "Old v2", make: "BMW", modelName: "Z4", year: 2003)
        oldContext.insert(vehicle)
        oldContext.insert(LocalStoreVersion(sourceFingerprint: "t05-fingerprint"))
        try oldContext.save()
        let pointer: [String: Any] = ["schemaVersion": 2, "storeName": storeName,
                                      "sourceFingerprint": "t05-fingerprint"]
        let pointerURL = directory.appendingPathComponent("CartrackV2/active-store.json")
        try JSONSerialization.data(withJSONObject: pointer).write(to: pointerURL, options: .atomic)

        let upgraded = try CartrackModelContainer.make(applicationSupportURL: directory,
                                                        legacyStoreURL: directory.appendingPathComponent("unused-v1.store"))
        let context = ModelContext(upgraded)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Vehicle>()).first?.id, vehicle.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncMetadataRecord>()).first?.ownerID, vehicle.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LocalPhotoAsset>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<OCRFieldEvidence>()).count, 0)
        let reopened = try CartrackModelContainer.make(applicationSupportURL: directory,
                                                        legacyStoreURL: directory.appendingPathComponent("unused-v1.store"))
        XCTAssertEqual(try ModelContext(reopened).fetch(FetchDescriptor<SyncMetadataRecord>()).count, 1)
    }

    private func metadata() -> SyncMetadata {
        SyncMetadata(createdAt: .now, updatedAt: .now)
    }

    private func vehicle(name: String) -> VehicleRecord {
        VehicleRecord(id: UUID(), name: name, make: "BMW", modelName: "Z4", year: 2003,
                      engine: "2.5i", plate: "", odometerUnit: .miles,
                      tankCapacityGallons: 14, fuelScaleMax: 8, fuelScaleStep: 0.25,
                      reserveThresholdRatio: Decimal(string: "0.10")!,
                      fuelEconomyReferenceKilometersPerGallon: 80, notes: "",
                      sync: metadata())
    }
}
