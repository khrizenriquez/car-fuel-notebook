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
}
