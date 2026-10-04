import Foundation

struct SyncMetadata: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var revision: Int64
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var originDeviceID: UUID?
    var lastSyncedRevision: Int64?

    init(
        schemaVersion: Int = 2,
        revision: Int64 = 1,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceID: UUID? = nil,
        lastSyncedRevision: Int64? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceID = originDeviceID
        self.lastSyncedRevision = lastSyncedRevision
    }
}

// No SwiftData types appear in these records. Monetary values stay Decimal in the domain;
// the v1 Double-backed store is translated at the persistence boundary.
struct VehicleRecord: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var make: String
    var modelName: String
    var year: Int
    var engine: String
    var plate: String
    var odometerUnit: OdometerUnit
    var tankCapacityGallons: Decimal
    var fuelScaleMax: Decimal
    var fuelScaleStep: Decimal
    var reserveThresholdRatio: Decimal
    var fuelEconomyReferenceKilometersPerGallon: Decimal
    var notes: String
    var sync: SyncMetadata
}

struct FuelEntryRecord: Codable, Equatable, Sendable {
    var id: UUID
    var vehicleID: UUID
    var occurredAt: Date
    var odometerKilometers: Decimal
    var tripKilometers: Decimal?
    var volumeGallons: Decimal
    var unitPrice: Decimal
    var totalCost: Decimal
    var currencyCode: String
    var isFullTank: Bool
    var fuelLevelRemaining: Decimal?
    var stationName: String
    var latitude: Decimal?
    var longitude: Decimal?
    var notes: String
    var sourceSessionID: UUID?
    var sync: SyncMetadata
}

struct UsageSnapshotRecord: Codable, Equatable, Sendable {
    var id: UUID
    var vehicleID: UUID
    var occurredAt: Date
    var odometerKilometers: Decimal
    var tripKilometers: Decimal?
    var fuelLevelRemaining: Decimal?
    var latitude: Decimal?
    var longitude: Decimal?
    var notes: String
    var sourceSessionID: UUID?
    var sync: SyncMetadata
}

struct LocalPhotoRecord: Codable, Equatable, Sendable {
    var id: UUID
    var sessionID: UUID?
    var eventID: UUID?
    var kind: String
    var localRelativePath: String
    var sha256: String
    var pixelWidth: Int
    var pixelHeight: Int
    var byteCount: Int
    var mimeType: String
    var capturedAt: Date?
    var optimizationState: String
    var createdAt: Date
}

struct OCRFieldRecord: Codable, Equatable, Sendable {
    var id: UUID
    var sessionID: UUID
    var ownerEventID: UUID?
    var field: String
    var rawText: String?
    var normalizedValue: String?
    var unit: String?
    var confidence: Decimal
    var confidenceBand: String
    var sourcePhotoID: UUID?
    var validationCodes: [String]
    var wasManuallyCorrected: Bool
    var algorithmVersion: String
}

enum RepositoryError: Error, Equatable, Sendable {
    case notFound
    case conflict
    case invalidRecord(String)

    var code: String {
        switch self {
        case .notFound: "entity.notFound"
        case .conflict: "repository.conflict"
        case .invalidRecord: "repository.invalidRecord"
        }
    }
}

@MainActor
protocol VehicleRepository {
    func all() async throws -> [VehicleRecord]
    func find(id: UUID) async throws -> VehicleRecord?
    func save(_ record: VehicleRecord) async throws
}

@MainActor
protocol FuelEntryRepository {
    func all(vehicleID: UUID) async throws -> [FuelEntryRecord]
    func find(id: UUID) async throws -> FuelEntryRecord?
    func save(_ record: FuelEntryRecord) async throws
}

@MainActor
protocol UsageSnapshotRepository {
    func all(vehicleID: UUID) async throws -> [UsageSnapshotRecord]
    func find(id: UUID) async throws -> UsageSnapshotRecord?
    func save(_ record: UsageSnapshotRecord) async throws
}

@MainActor
protocol PhotoAssetRepository {
    func all(sessionID: UUID) async throws -> [LocalPhotoRecord]
    func save(_ record: LocalPhotoRecord) async throws
}

@MainActor
protocol OCRFieldEvidenceRepository {
    func all(sessionID: UUID) async throws -> [OCRFieldRecord]
    func save(_ record: OCRFieldRecord) async throws
}
