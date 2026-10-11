import Foundation
import XCTest
@testable import CartrackCore

final class V2DomainCoreTests: XCTestCase {
    func testRepositoryErrorsExposeStableCodesWithoutSensitiveDetails() {
        XCTAssertEqual(RepositoryError.notFound.code, "entity.notFound")
        XCTAssertEqual(RepositoryError.conflict.code, "repository.conflict")
        XCTAssertEqual(RepositoryError.invalidRecord("private raw value").code,
                       "repository.invalidRecord")
    }

    func testSyncMetadataCodableRoundTripKeepsRevisionAndTombstone() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = SyncMetadata(schemaVersion: 2, revision: 7,
                                    createdAt: timestamp, updatedAt: timestamp,
                                    deletedAt: timestamp, originDeviceID: UUID(),
                                    lastSyncedRevision: 6)
        let encoded = try JSONEncoder().encode(metadata)
        XCTAssertEqual(try JSONDecoder().decode(SyncMetadata.self, from: encoded), metadata)
    }

    func testCanonicalFuelRecordDoesNotCarryPhotoBytesOrPaths() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let record = FuelEntryRecord(
            id: UUID(), vehicleID: UUID(), occurredAt: timestamp,
            odometerKilometers: Decimal(string: "175012.9")!,
            tripKilometers: Decimal(string: "945.1")!,
            volumeGallons: Decimal(string: "11.123")!,
            unitPrice: Decimal(string: "42.527")!,
            totalCost: Decimal(string: "473.02")!,
            currencyCode: "GTQ", isFullTank: true,
            fuelLevelRemaining: 8, stationName: "Station",
            latitude: nil, longitude: nil, notes: "", sourceSessionID: UUID(),
            sync: SyncMetadata(createdAt: timestamp, updatedAt: timestamp)
        )
        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(FuelEntryRecord.self, from: encoded)
        XCTAssertEqual(decoded, record)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(json.contains("localRelativePath"))
        XCTAssertFalse(json.contains("imageData"))
        XCTAssertFalse(json.contains("base64"))
    }

    func testSyncDTOsKeepExactDecimalsAndExcludeLocalOrSensitiveFields() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = SyncMetadata(revision: 4, createdAt: timestamp, updatedAt: timestamp)
        let vehicle = VehicleRecord(
            id: UUID(), name: "Roadster", make: "BMW", modelName: "Z4", year: 2003,
            engine: "2.5i", plate: "P123ABC", odometerUnit: .miles,
            tankCapacityGallons: Decimal(string: "14.000")!, fuelScaleMax: 8,
            fuelScaleStep: Decimal(string: "0.25")!, reserveThresholdRatio: Decimal(string: "0.125")!,
            fuelEconomyReferenceKilometersPerGallon: Decimal(string: "85.9")!,
            notes: "private note", sync: metadata
        )
        let fuel = FuelEntryRecord(
            id: UUID(), vehicleID: vehicle.id, occurredAt: timestamp,
            odometerKilometers: Decimal(string: "175012.9")!, tripKilometers: Decimal(string: "945.1")!,
            volumeGallons: Decimal(string: "11.123")!, unitPrice: Decimal(string: "42.527")!,
            totalCost: Decimal(string: "473.02")!, currencyCode: "GTQ", isFullTank: true,
            fuelLevelRemaining: Decimal(string: "1.25")!, stationName: "Public station",
            latitude: Decimal(string: "14.6")!, longitude: Decimal(string: "-90.5")!,
            notes: "private route", sourceSessionID: UUID(), sync: metadata
        )
        let evidence = OCRFieldRecord(
            id: UUID(), sessionID: UUID(), ownerEventID: fuel.id, field: "odometer",
            rawText: "109,729 miles", normalizedValue: "109729", unit: "mi", confidence: 0.93,
            confidenceBand: "high", sourcePhotoID: UUID(), validationCodes: ["range.valid"],
            wasManuallyCorrected: false, algorithmVersion: "field-confidence-v1"
        )
        let documents = [try SyncDTOFactory.vehicle(vehicle), try SyncDTOFactory.fuelEntry(fuel),
                         try XCTUnwrap(SyncDTOFactory.ocrEvidence(evidence))]
        let data = try JSONEncoder().encode(documents)
        let decoded = try JSONDecoder().decode([SyncRecordDTO].self, from: data)
        XCTAssertEqual(decoded, documents)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("42.527"))
        XCTAssertFalse(json.contains("P123ABC"))
        XCTAssertFalse(json.contains("private note"))
        XCTAssertFalse(json.contains("private route"))
        XCTAssertFalse(json.contains("109,729 miles"))
        XCTAssertFalse(json.contains("sourcePhotoID"))
        XCTAssertFalse(json.contains("localRelativePath"))
        XCTAssertFalse(json.contains("imageData"))
        XCTAssertFalse(json.contains("latitude"))
    }

    func testStructuredSyncConflictResolutionIsIdempotentAndProtectsCriticalFields() throws {
        let id = UUID()
        let vehicleID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        func document(revision: Int64, updatedAt: Date, odometer: String, station: String) throws -> SyncRecordDTO {
            try SyncRecordDTO(
                id: id, metadata: SyncRecordMetadata(revision: revision, createdAt: timestamp,
                                                      updatedAt: updatedAt),
                payload: .fuelEntry(SyncFuelEntryPayload(
                    vehicleID: vehicleID, occurredAt: timestamp,
                    odometerKilometers: try SyncDecimal(rawValue: odometer), tripKilometers: nil,
                    volumeGallons: try SyncDecimal(rawValue: "11.123"),
                    unitPrice: try SyncDecimal(rawValue: "42.527"), totalCost: try SyncDecimal(rawValue: "473.02"),
                    currencyCode: "GTQ", isFullTank: true, fuelLevelRemaining: nil,
                    stationName: station
                ))
            )
        }
        let local = try document(revision: 4, updatedAt: timestamp, odometer: "175012.9", station: "A")
        XCTAssertEqual(try StructuredSyncConflictResolver.resolve(local: local, remote: local), .alreadyApplied)
        XCTAssertEqual(try StructuredSyncConflictResolver.resolve(
            local: local, remote: document(revision: 5, updatedAt: timestamp, odometer: "175012.9", station: "A")
        ), .applyRemote)

        let nonCritical = try document(revision: 4, updatedAt: timestamp.addingTimeInterval(1),
                                       odometer: "175012.9", station: "B")
        XCTAssertEqual(try StructuredSyncConflictResolver.resolve(local: local, remote: nonCritical), .applyRemote)

        let critical = try document(revision: 4, updatedAt: timestamp.addingTimeInterval(1),
                                    odometer: "175013.9", station: "A")
        XCTAssertEqual(
            try StructuredSyncConflictResolver.resolve(local: local, remote: critical),
            .needsUserResolution(SyncConflict(id: id, kind: .fuelEntry, revision: 4,
                                               criticalFields: ["odometerKilometers"]))
        )
    }

    func testSyncPayloadBudgetIsUnderFiveMegabytesPerYearAndRejectsInvalidDecimals() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = try SyncRecordDTO(
            id: UUID(), metadata: SyncRecordMetadata(revision: 1, createdAt: timestamp, updatedAt: timestamp),
            payload: .usageSnapshot(SyncUsageSnapshotPayload(
                vehicleID: UUID(), occurredAt: timestamp, odometerKilometers: try SyncDecimal(rawValue: "175012.9"),
                tripKilometers: try SyncDecimal(rawValue: "81.3"), fuelLevelRemaining: try SyncDecimal(rawValue: "1.25")
            ))
        )
        XCTAssertLessThan(try SyncPayloadBudget.projectedAnnualByteCount(sample: [snapshot]),
                          SyncPayloadBudget.annualLimitBytes)
        XCTAssertThrowsError(try SyncDecimal(rawValue: "not-a-decimal"))
        XCTAssertThrowsError(try JSONDecoder().decode(SyncDecimal.self, from: Data("\"not-a-decimal\"".utf8)))
    }
}
