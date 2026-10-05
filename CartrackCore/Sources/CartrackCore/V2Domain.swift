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

// MARK: - v2.1 structured sync readiness

/// Exact decimal transport for the future database boundary. JSON numbers are deliberately not
/// used for money, odometers, or calibrated fuel values because an intermediate JavaScript or
/// database client could otherwise round them.
struct SyncDecimal: Equatable, Sendable, Hashable {
    let rawValue: String

    init(_ value: Decimal) {
        rawValue = NSDecimalNumber(decimal: value).stringValue
    }

    init(rawValue: String) throws {
        guard let value = Decimal(string: rawValue, locale: Locale(identifier: "en_US_POSIX")),
              NSDecimalNumber(decimal: value) != .notANumber else {
            throw SyncDTOError.invalidDecimal(rawValue)
        }
        self.init(value)
    }

    var decimalValue: Decimal {
        // The failable initializer is the only public creation path for untrusted strings.
        Decimal(string: rawValue, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }
}

extension SyncDecimal: Codable {
    init(from decoder: Decoder) throws {
        try self.init(rawValue: decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum SyncRecordKind: String, Codable, CaseIterable, Sendable {
    case vehicle
    case fuelEntry
    case usageSnapshot
    case ocrFieldEvidence
}

struct SyncRecordMetadata: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let revision: Int64
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(schemaVersion: Int = 2, revision: Int64,
         createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

struct SyncVehiclePayload: Codable, Equatable, Sendable {
    let name: String
    let make: String
    let modelName: String
    let year: Int
    let engine: String
    let odometerUnit: OdometerUnit
    let tankCapacityGallons: SyncDecimal
    let fuelScaleMax: SyncDecimal
    let fuelScaleStep: SyncDecimal
    let reserveThresholdRatio: SyncDecimal
    let fuelEconomyReferenceKilometersPerGallon: SyncDecimal
}

struct SyncFuelEntryPayload: Codable, Equatable, Sendable {
    let vehicleID: UUID
    let occurredAt: Date
    let odometerKilometers: SyncDecimal
    let tripKilometers: SyncDecimal?
    let volumeGallons: SyncDecimal
    let unitPrice: SyncDecimal
    let totalCost: SyncDecimal
    let currencyCode: String
    let isFullTank: Bool
    let fuelLevelRemaining: SyncDecimal?
    let stationName: String
}

struct SyncUsageSnapshotPayload: Codable, Equatable, Sendable {
    let vehicleID: UUID
    let occurredAt: Date
    let odometerKilometers: SyncDecimal
    let tripKilometers: SyncDecimal?
    let fuelLevelRemaining: SyncDecimal?
}

struct SyncOCRFieldEvidencePayload: Codable, Equatable, Sendable {
    let ownerEventID: UUID
    let field: String
    let normalizedValue: String?
    let unit: String?
    let confidence: SyncDecimal
    let confidenceBand: String
    let validationCodes: [String]
    let wasManuallyCorrected: Bool
    let algorithmVersion: String
}

enum SyncPayload: Equatable, Sendable {
    case vehicle(SyncVehiclePayload)
    case fuelEntry(SyncFuelEntryPayload)
    case usageSnapshot(SyncUsageSnapshotPayload)
    case ocrFieldEvidence(SyncOCRFieldEvidencePayload)

    var kind: SyncRecordKind {
        switch self {
        case .vehicle: .vehicle
        case .fuelEntry: .fuelEntry
        case .usageSnapshot: .usageSnapshot
        case .ocrFieldEvidence: .ocrFieldEvidence
        }
    }

    /// Only these fields need semantic protection when two writes claim the same revision.
    var criticalFieldValues: [String: String] {
        switch self {
        case .vehicle:
            return [:]
        case .fuelEntry(let value):
            return ["vehicleID": value.vehicleID.uuidString,
                    "odometerKilometers": value.odometerKilometers.rawValue,
                    "volumeGallons": value.volumeGallons.rawValue,
                    "unitPrice": value.unitPrice.rawValue,
                    "totalCost": value.totalCost.rawValue]
        case .usageSnapshot(let value):
            return ["vehicleID": value.vehicleID.uuidString,
                    "odometerKilometers": value.odometerKilometers.rawValue]
        case .ocrFieldEvidence:
            return [:]
        }
    }
}

extension SyncPayload: Codable {
    private enum CodingKeys: String, CodingKey { case kind, vehicle, fuelEntry, usageSnapshot, ocrFieldEvidence }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(SyncRecordKind.self, forKey: .kind) {
        case .vehicle:
            self = .vehicle(try container.decode(SyncVehiclePayload.self, forKey: .vehicle))
        case .fuelEntry:
            self = .fuelEntry(try container.decode(SyncFuelEntryPayload.self, forKey: .fuelEntry))
        case .usageSnapshot:
            self = .usageSnapshot(try container.decode(SyncUsageSnapshotPayload.self, forKey: .usageSnapshot))
        case .ocrFieldEvidence:
            self = .ocrFieldEvidence(try container.decode(SyncOCRFieldEvidencePayload.self, forKey: .ocrFieldEvidence))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .vehicle(let value): try container.encode(value, forKey: .vehicle)
        case .fuelEntry(let value): try container.encode(value, forKey: .fuelEntry)
        case .usageSnapshot(let value): try container.encode(value, forKey: .usageSnapshot)
        case .ocrFieldEvidence(let value): try container.encode(value, forKey: .ocrFieldEvidence)
        }
    }
}

/// Network-free transport document. `ownerID` will be populated from Auth in v2.1; its absence
/// is valid only while running locally in v2.
struct SyncRecordDTO: Equatable, Sendable {
    let id: UUID
    let ownerID: UUID?
    let metadata: SyncRecordMetadata
    let payload: SyncPayload

    var kind: SyncRecordKind { payload.kind }

    init(id: UUID, ownerID: UUID? = nil, metadata: SyncRecordMetadata, payload: SyncPayload) throws {
        guard metadata.schemaVersion >= 2, metadata.revision > 0,
              metadata.updatedAt >= metadata.createdAt else {
            throw SyncDTOError.invalidMetadata
        }
        self.id = id
        self.ownerID = ownerID
        self.metadata = metadata
        self.payload = payload
    }
}

extension SyncRecordDTO: Codable {
    private enum CodingKeys: String, CodingKey { case id, ownerID, metadata, payload }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            ownerID: container.decodeIfPresent(UUID.self, forKey: .ownerID),
            metadata: container.decode(SyncRecordMetadata.self, forKey: .metadata),
            payload: container.decode(SyncPayload.self, forKey: .payload)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(ownerID, forKey: .ownerID)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(payload, forKey: .payload)
    }
}

enum SyncDTOError: Error, Equatable, Sendable {
    case invalidDecimal(String)
    case invalidMetadata
    case incompatibleRecord
}

enum SyncDTOFactory {
    static func vehicle(_ record: VehicleRecord, ownerID: UUID? = nil) throws -> SyncRecordDTO {
        try SyncRecordDTO(
            id: record.id, ownerID: ownerID, metadata: metadata(record.sync),
            payload: .vehicle(SyncVehiclePayload(
                name: record.name, make: record.make, modelName: record.modelName, year: record.year,
                engine: record.engine, odometerUnit: record.odometerUnit,
                tankCapacityGallons: SyncDecimal(record.tankCapacityGallons),
                fuelScaleMax: SyncDecimal(record.fuelScaleMax), fuelScaleStep: SyncDecimal(record.fuelScaleStep),
                reserveThresholdRatio: SyncDecimal(record.reserveThresholdRatio),
                fuelEconomyReferenceKilometersPerGallon: SyncDecimal(record.fuelEconomyReferenceKilometersPerGallon)
            ))
        )
    }

    static func fuelEntry(_ record: FuelEntryRecord, ownerID: UUID? = nil) throws -> SyncRecordDTO {
        try SyncRecordDTO(
            id: record.id, ownerID: ownerID, metadata: metadata(record.sync),
            payload: .fuelEntry(SyncFuelEntryPayload(
                vehicleID: record.vehicleID, occurredAt: record.occurredAt,
                odometerKilometers: SyncDecimal(record.odometerKilometers),
                tripKilometers: record.tripKilometers.map(SyncDecimal.init),
                volumeGallons: SyncDecimal(record.volumeGallons), unitPrice: SyncDecimal(record.unitPrice),
                totalCost: SyncDecimal(record.totalCost), currencyCode: record.currencyCode,
                isFullTank: record.isFullTank,
                fuelLevelRemaining: record.fuelLevelRemaining.map(SyncDecimal.init),
                stationName: record.stationName
            ))
        )
    }

    static func usageSnapshot(_ record: UsageSnapshotRecord, ownerID: UUID? = nil) throws -> SyncRecordDTO {
        try SyncRecordDTO(
            id: record.id, ownerID: ownerID, metadata: metadata(record.sync),
            payload: .usageSnapshot(SyncUsageSnapshotPayload(
                vehicleID: record.vehicleID, occurredAt: record.occurredAt,
                odometerKilometers: SyncDecimal(record.odometerKilometers),
                tripKilometers: record.tripKilometers.map(SyncDecimal.init),
                fuelLevelRemaining: record.fuelLevelRemaining.map(SyncDecimal.init)
            ))
        )
    }

    static func ocrEvidence(_ record: OCRFieldRecord, ownerID: UUID? = nil) throws -> SyncRecordDTO? {
        guard let ownerEventID = record.ownerEventID else { return nil }
        return try SyncRecordDTO(
            id: record.id, ownerID: ownerID,
            metadata: SyncRecordMetadata(revision: 1, createdAt: .now, updatedAt: .now),
            payload: .ocrFieldEvidence(SyncOCRFieldEvidencePayload(
                ownerEventID: ownerEventID, field: record.field, normalizedValue: record.normalizedValue,
                unit: record.unit, confidence: SyncDecimal(record.confidence),
                confidenceBand: record.confidenceBand, validationCodes: record.validationCodes,
                wasManuallyCorrected: record.wasManuallyCorrected, algorithmVersion: record.algorithmVersion
            ))
        )
    }

    private static func metadata(_ value: SyncMetadata) -> SyncRecordMetadata {
        SyncRecordMetadata(schemaVersion: value.schemaVersion, revision: value.revision,
                           createdAt: value.createdAt, updatedAt: value.updatedAt,
                           deletedAt: value.deletedAt)
    }
}

enum SyncApplyDecision: Equatable, Sendable {
    case applyRemote
    case keepLocal
    case alreadyApplied
    case needsUserResolution(SyncConflict)
}

struct SyncConflict: Equatable, Sendable {
    let id: UUID
    let kind: SyncRecordKind
    let revision: Int64
    let criticalFields: [String]
}

enum StructuredSyncConflictResolver {
    /// Idempotency is keyed by `(id, revision)`. A more recent revision wins for non-critical
    /// fields. Different critical data at an equal revision is deliberately left unresolved.
    static func resolve(local: SyncRecordDTO, remote: SyncRecordDTO) throws -> SyncApplyDecision {
        guard local.id == remote.id, local.kind == remote.kind, local.ownerID == remote.ownerID else {
            throw SyncDTOError.incompatibleRecord
        }
        if remote.metadata.revision > local.metadata.revision { return .applyRemote }
        if remote.metadata.revision < local.metadata.revision { return .keepLocal }
        if remote == local { return .alreadyApplied }

        let critical = Set(local.payload.criticalFieldValues.keys)
            .union(remote.payload.criticalFieldValues.keys)
            .filter { local.payload.criticalFieldValues[$0] != remote.payload.criticalFieldValues[$0] }
            .sorted()
        if !critical.isEmpty {
            return .needsUserResolution(SyncConflict(id: local.id, kind: local.kind,
                                                      revision: local.metadata.revision,
                                                      criticalFields: critical))
        }
        return remote.metadata.updatedAt > local.metadata.updatedAt ? .applyRemote : .keepLocal
    }
}

enum SyncPayloadBudget {
    static let annualLimitBytes = 5_000_000
    static let expectedEventsPerWeek = 5
    static let weeksPerYear = 52

    static func serializedByteCount(_ records: [SyncRecordDTO]) throws -> Int {
        try JSONEncoder().encode(records).count
    }

    static func projectedAnnualByteCount(sample: [SyncRecordDTO]) throws -> Int {
        guard !sample.isEmpty else { return 0 }
        let perRecord = try serializedByteCount(sample) / sample.count
        return perRecord * expectedEventsPerWeek * weeksPerYear
    }
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
