import Foundation
import SwiftData

private enum DecimalBridge {
    static func decimal(_ value: Double) -> Decimal {
        Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    static func decimal(_ value: Double?) -> Decimal? { value.map(decimal) }

    static func double(_ value: Decimal) throws -> Double {
        let result = NSDecimalNumber(decimal: value).doubleValue
        guard result.isFinite else { throw RepositoryError.invalidRecord("decimal.outOfRange") }
        return result
    }

    static func double(_ value: Decimal?) throws -> Double? { try value.map(double) }
}

@MainActor
private enum RepositoryStorage {
    static func metadata(for ownerID: UUID, in context: ModelContext) throws -> SyncMetadataRecord? {
        try context.fetch(FetchDescriptor<SyncMetadataRecord>()).first { $0.ownerID == ownerID }
    }

    static func extras(for ownerID: UUID, in context: ModelContext) throws -> V2RecordExtras? {
        try context.fetch(FetchDescriptor<V2RecordExtras>()).first { $0.ownerID == ownerID }
    }

    static func sync(_ stored: SyncMetadataRecord?, createdAt: Date, updatedAt: Date) -> SyncMetadata {
        guard let stored else { return SyncMetadata(createdAt: createdAt, updatedAt: updatedAt) }
        return SyncMetadata(schemaVersion: stored.schemaVersion, revision: stored.revision,
                            createdAt: stored.createdAt, updatedAt: stored.updatedAt,
                            deletedAt: stored.deletedAt, originDeviceID: stored.originDeviceID,
                            lastSyncedRevision: stored.lastSyncedRevision)
    }

    static func saveSync(
        _ incoming: SyncMetadata, ownerID: UUID, kind: String, in context: ModelContext
    ) throws {
        if let stored = try metadata(for: ownerID, in: context) {
            guard stored.ownerKindRawValue == kind, incoming.revision == stored.revision else {
                throw RepositoryError.conflict
            }
            stored.revision += 1
            stored.updatedAt = .now
            stored.deletedAt = incoming.deletedAt
            stored.originDeviceID = incoming.originDeviceID
            stored.lastSyncedRevision = incoming.lastSyncedRevision
        } else {
            guard incoming.revision == 1 else { throw RepositoryError.conflict }
            context.insert(SyncMetadataRecord(ownerID: ownerID, ownerKindRawValue: kind,
                                              schemaVersion: 2, revision: incoming.revision,
                                              createdAt: incoming.createdAt,
                                              updatedAt: incoming.updatedAt,
                                              deletedAt: incoming.deletedAt,
                                              originDeviceID: incoming.originDeviceID,
                                              lastSyncedRevision: incoming.lastSyncedRevision))
        }
    }

    static func saveExtras(
        ownerID: UUID, reserve: Decimal? = nil, currency: String? = nil,
        sessionID: UUID? = nil, in context: ModelContext
    ) throws {
        let stored = try extras(for: ownerID, in: context)
        if let stored {
            stored.reserveThresholdRatioDecimal = reserve.map(String.init(describing:))
            stored.currencyCode = currency
            stored.sourceSessionID = sessionID
        } else {
            context.insert(V2RecordExtras(ownerID: ownerID,
                                          reserveThresholdRatioDecimal: reserve.map(String.init(describing:)),
                                          currencyCode: currency, sourceSessionID: sessionID))
        }
    }

    static func vehicle(id: UUID, in context: ModelContext) throws -> Vehicle? {
        try context.fetch(FetchDescriptor<Vehicle>()).first { $0.id == id }
    }
}

@MainActor
final class SwiftDataVehicleRepository: VehicleRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func all() async throws -> [VehicleRecord] {
        try context.fetch(FetchDescriptor<Vehicle>())
            .map(project)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func find(id: UUID) async throws -> VehicleRecord? {
        try RepositoryStorage.vehicle(id: id, in: context).map(project)
    }

    func save(_ record: VehicleRecord) async throws {
        guard !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              record.reserveThresholdRatio >= 0, record.reserveThresholdRatio <= 1 else {
            throw RepositoryError.invalidRecord("vehicle.invalid")
        }
        let existing = try RepositoryStorage.vehicle(id: record.id, in: context)
        try RepositoryStorage.saveSync(record.sync, ownerID: record.id, kind: "vehicle",
                                       in: context)
        let vehicle = existing ?? Vehicle(id: record.id, name: record.name, make: record.make,
                                          modelName: record.modelName, year: record.year,
                                          createdAt: record.sync.createdAt)
        vehicle.name = record.name
        vehicle.make = record.make
        vehicle.modelName = record.modelName
        vehicle.year = record.year
        vehicle.engine = record.engine
        vehicle.plate = record.plate
        vehicle.odometerUnit = record.odometerUnit
        vehicle.tankCapacityGallons = try DecimalBridge.double(record.tankCapacityGallons)
        vehicle.fuelScaleMax = try DecimalBridge.double(record.fuelScaleMax)
        vehicle.fuelScaleStep = try DecimalBridge.double(record.fuelScaleStep)
        vehicle.fuelEconomyReferenceKilometersPerGallon = try DecimalBridge.double(record.fuelEconomyReferenceKilometersPerGallon)
        vehicle.notes = record.notes
        if existing == nil { context.insert(vehicle) }
        try RepositoryStorage.saveExtras(ownerID: record.id, reserve: record.reserveThresholdRatio,
                                         in: context)
        try context.save()
    }

    private func project(_ vehicle: Vehicle) throws -> VehicleRecord {
        let metadata = try RepositoryStorage.metadata(for: vehicle.id, in: context)
        let extras = try RepositoryStorage.extras(for: vehicle.id, in: context)
        let reserve = Decimal(string: extras?.reserveThresholdRatioDecimal ?? "0.125") ?? 0.125
        return VehicleRecord(id: vehicle.id, name: vehicle.name, make: vehicle.make,
                             modelName: vehicle.modelName, year: vehicle.year, engine: vehicle.engine,
                             plate: vehicle.plate, odometerUnit: vehicle.odometerUnit,
                             tankCapacityGallons: DecimalBridge.decimal(vehicle.tankCapacityGallons),
                             fuelScaleMax: DecimalBridge.decimal(vehicle.fuelScaleMax),
                             fuelScaleStep: DecimalBridge.decimal(vehicle.fuelScaleStep),
                             reserveThresholdRatio: reserve,
                             fuelEconomyReferenceKilometersPerGallon: DecimalBridge.decimal(vehicle.fuelEconomyReferenceKilometersPerGallon),
                             notes: vehicle.notes,
                             sync: RepositoryStorage.sync(metadata, createdAt: vehicle.createdAt,
                                                          updatedAt: vehicle.createdAt))
    }
}

@MainActor
final class SwiftDataFuelEntryRepository: FuelEntryRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func all(vehicleID: UUID) async throws -> [FuelEntryRecord] {
        try context.fetch(FetchDescriptor<FuelFillEvent>())
            .filter { $0.vehicle?.id == vehicleID }
            .map(project)
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    func find(id: UUID) async throws -> FuelEntryRecord? {
        try context.fetch(FetchDescriptor<FuelFillEvent>()).first { $0.id == id }.map(project)
    }

    func save(_ record: FuelEntryRecord) async throws {
        guard let vehicle = try RepositoryStorage.vehicle(id: record.vehicleID, in: context) else {
            throw RepositoryError.notFound
        }
        guard record.currencyCode.count == 3 else { throw RepositoryError.invalidRecord("currency.invalid") }
        let existing = try context.fetch(FetchDescriptor<FuelFillEvent>()).first { $0.id == record.id }
        try RepositoryStorage.saveSync(record.sync, ownerID: record.id, kind: "fuelEntry",
                                       in: context)
        let fill = existing ?? FuelFillEvent(id: record.id, date: record.occurredAt,
                                             vehicle: vehicle, createdAt: record.sync.createdAt)
        fill.vehicle = vehicle
        fill.date = record.occurredAt
        fill.odometerKilometers = try DecimalBridge.double(record.odometerKilometers)
        fill.tripKilometers = try DecimalBridge.double(record.tripKilometers)
        fill.gallons = try DecimalBridge.double(record.volumeGallons)
        fill.pricePerGallon = try DecimalBridge.double(record.unitPrice)
        fill.totalCost = try DecimalBridge.double(record.totalCost)
        fill.isFullTank = record.isFullTank
        fill.fuelLevelRemaining = try DecimalBridge.double(record.fuelLevelRemaining ?? DecimalBridge.decimal(vehicle.fuelScaleMax))
        fill.stationName = record.stationName
        fill.latitude = try DecimalBridge.double(record.latitude)
        fill.longitude = try DecimalBridge.double(record.longitude)
        fill.notes = record.notes
        fill.updatedAt = .now
        if existing == nil { context.insert(fill) }
        try RepositoryStorage.saveExtras(ownerID: record.id, currency: record.currencyCode,
                                         sessionID: record.sourceSessionID, in: context)
        try context.save()
    }

    private func project(_ fill: FuelFillEvent) throws -> FuelEntryRecord {
        guard let vehicleID = fill.vehicle?.id else { throw RepositoryError.invalidRecord("vehicle.missing") }
        let metadata = try RepositoryStorage.metadata(for: fill.id, in: context)
        let extras = try RepositoryStorage.extras(for: fill.id, in: context)
        return FuelEntryRecord(id: fill.id, vehicleID: vehicleID, occurredAt: fill.date,
                               odometerKilometers: DecimalBridge.decimal(fill.odometerKilometers),
                               tripKilometers: DecimalBridge.decimal(fill.tripKilometers),
                               volumeGallons: DecimalBridge.decimal(fill.gallons),
                               unitPrice: DecimalBridge.decimal(fill.pricePerGallon),
                               totalCost: DecimalBridge.decimal(fill.totalCost),
                               currencyCode: extras?.currencyCode ?? "GTQ",
                               isFullTank: fill.isFullTank,
                               fuelLevelRemaining: DecimalBridge.decimal(fill.fuelLevelRemaining),
                               stationName: fill.stationName,
                               latitude: DecimalBridge.decimal(fill.latitude),
                               longitude: DecimalBridge.decimal(fill.longitude), notes: fill.notes,
                               sourceSessionID: extras?.sourceSessionID,
                               sync: RepositoryStorage.sync(metadata, createdAt: fill.createdAt,
                                                            updatedAt: fill.updatedAt))
    }
}

@MainActor
final class SwiftDataUsageSnapshotRepository: UsageSnapshotRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func all(vehicleID: UUID) async throws -> [UsageSnapshotRecord] {
        try context.fetch(FetchDescriptor<SnapshotEvent>())
            .filter { $0.vehicle?.id == vehicleID }
            .map(project)
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    func find(id: UUID) async throws -> UsageSnapshotRecord? {
        try context.fetch(FetchDescriptor<SnapshotEvent>()).first { $0.id == id }.map(project)
    }

    func save(_ record: UsageSnapshotRecord) async throws {
        guard let vehicle = try RepositoryStorage.vehicle(id: record.vehicleID, in: context) else {
            throw RepositoryError.notFound
        }
        let existing = try context.fetch(FetchDescriptor<SnapshotEvent>()).first { $0.id == record.id }
        try RepositoryStorage.saveSync(record.sync, ownerID: record.id, kind: "usageSnapshot",
                                       in: context)
        let snapshot = existing ?? SnapshotEvent(id: record.id, date: record.occurredAt,
                                                 vehicle: vehicle, createdAt: record.sync.createdAt)
        snapshot.vehicle = vehicle
        snapshot.date = record.occurredAt
        snapshot.odometerKilometers = try DecimalBridge.double(record.odometerKilometers)
        snapshot.tripKilometers = try DecimalBridge.double(record.tripKilometers)
        snapshot.fuelLevelRemaining = try DecimalBridge.double(record.fuelLevelRemaining ?? DecimalBridge.decimal(vehicle.fuelScaleMax))
        snapshot.latitude = try DecimalBridge.double(record.latitude)
        snapshot.longitude = try DecimalBridge.double(record.longitude)
        snapshot.notes = record.notes
        snapshot.updatedAt = .now
        if existing == nil { context.insert(snapshot) }
        try RepositoryStorage.saveExtras(ownerID: record.id, sessionID: record.sourceSessionID,
                                         in: context)
        try context.save()
    }

    private func project(_ snapshot: SnapshotEvent) throws -> UsageSnapshotRecord {
        guard let vehicleID = snapshot.vehicle?.id else { throw RepositoryError.invalidRecord("vehicle.missing") }
        let metadata = try RepositoryStorage.metadata(for: snapshot.id, in: context)
        let extras = try RepositoryStorage.extras(for: snapshot.id, in: context)
        return UsageSnapshotRecord(id: snapshot.id, vehicleID: vehicleID, occurredAt: snapshot.date,
                                   odometerKilometers: DecimalBridge.decimal(snapshot.odometerKilometers),
                                   tripKilometers: DecimalBridge.decimal(snapshot.tripKilometers),
                                   fuelLevelRemaining: DecimalBridge.decimal(snapshot.fuelLevelRemaining),
                                   latitude: DecimalBridge.decimal(snapshot.latitude),
                                   longitude: DecimalBridge.decimal(snapshot.longitude), notes: snapshot.notes,
                                   sourceSessionID: extras?.sourceSessionID,
                                   sync: RepositoryStorage.sync(metadata, createdAt: snapshot.createdAt,
                                                                updatedAt: snapshot.updatedAt))
    }
}

@MainActor
final class SwiftDataPhotoAssetRepository: PhotoAssetRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func all(sessionID: UUID) async throws -> [LocalPhotoRecord] {
        try context.fetch(FetchDescriptor<LocalPhotoAsset>())
            .filter { $0.sessionID == sessionID }
            .map { LocalPhotoRecord(id: $0.id, sessionID: $0.sessionID, eventID: $0.eventID,
                                    kind: $0.kindRawValue, localRelativePath: $0.localRelativePath,
                                    sha256: $0.sha256, pixelWidth: $0.pixelWidth,
                                    pixelHeight: $0.pixelHeight, byteCount: $0.byteCount,
                                    mimeType: $0.mimeType, capturedAt: $0.capturedAt,
                                    optimizationState: $0.optimizationStateRawValue,
                                    createdAt: $0.createdAt) }
    }

    func save(_ record: LocalPhotoRecord) async throws {
        let components = record.localRelativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !record.localRelativePath.hasPrefix("/"), !components.contains(".."),
              !record.localRelativePath.isEmpty, record.byteCount >= 0,
              record.pixelWidth >= 0, record.pixelHeight >= 0,
              record.sha256.count == 64,
              record.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw RepositoryError.invalidRecord("photo.pathOrSize.invalid")
        }
        let existing = try context.fetch(FetchDescriptor<LocalPhotoAsset>()).first { $0.id == record.id }
        let asset = existing ?? LocalPhotoAsset(id: record.id, kindRawValue: record.kind,
                                                localRelativePath: record.localRelativePath,
                                                sha256: record.sha256, pixelWidth: record.pixelWidth,
                                                pixelHeight: record.pixelHeight,
                                                byteCount: record.byteCount, mimeType: record.mimeType,
                                                createdAt: record.createdAt)
        asset.sessionID = record.sessionID
        asset.eventID = record.eventID
        asset.kindRawValue = record.kind
        asset.localRelativePath = record.localRelativePath
        asset.sha256 = record.sha256
        asset.pixelWidth = record.pixelWidth
        asset.pixelHeight = record.pixelHeight
        asset.byteCount = record.byteCount
        asset.mimeType = record.mimeType
        asset.capturedAt = record.capturedAt
        asset.optimizationStateRawValue = record.optimizationState
        if existing == nil { context.insert(asset) }
        try context.save()
    }
}

@MainActor
final class SwiftDataOCRFieldEvidenceRepository: OCRFieldEvidenceRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func all(sessionID: UUID) async throws -> [OCRFieldRecord] {
        try context.fetch(FetchDescriptor<OCRFieldEvidence>())
            .filter { $0.sessionID == sessionID }
            .map { evidence in
                guard let confidence = Decimal(string: evidence.confidenceDecimal) else {
                    throw RepositoryError.invalidRecord("ocr.confidence.corrupt")
                }
                return OCRFieldRecord(id: evidence.id, sessionID: evidence.sessionID,
                                      ownerEventID: evidence.ownerEventID, field: evidence.fieldRawValue,
                                      rawText: evidence.rawText, normalizedValue: evidence.normalizedValue,
                                      unit: evidence.unit, confidence: confidence,
                                      confidenceBand: evidence.confidenceBandRawValue,
                                      sourcePhotoID: evidence.sourcePhotoID,
                                      validationCodes: evidence.validationCodes,
                                      wasManuallyCorrected: evidence.wasManuallyCorrected,
                                      algorithmVersion: evidence.algorithmVersion)
            }
    }

    func save(_ record: OCRFieldRecord) async throws {
        guard record.confidence >= 0, record.confidence <= 1,
              !record.field.isEmpty, !record.algorithmVersion.isEmpty else {
            throw RepositoryError.invalidRecord("ocr.evidence.invalid")
        }
        let existing = try context.fetch(FetchDescriptor<OCRFieldEvidence>()).first { $0.id == record.id }
        let evidence = existing ?? OCRFieldEvidence(id: record.id, sessionID: record.sessionID,
                                                    fieldRawValue: record.field,
                                                    confidenceDecimal: String(describing: record.confidence),
                                                    confidenceBandRawValue: record.confidenceBand,
                                                    algorithmVersion: record.algorithmVersion)
        evidence.sessionID = record.sessionID
        evidence.ownerEventID = record.ownerEventID
        evidence.fieldRawValue = record.field
        evidence.rawText = record.rawText
        evidence.normalizedValue = record.normalizedValue
        evidence.unit = record.unit
        evidence.confidenceDecimal = String(describing: record.confidence)
        evidence.confidenceBandRawValue = record.confidenceBand
        evidence.sourcePhotoID = record.sourcePhotoID
        evidence.validationCodes = record.validationCodes
        evidence.wasManuallyCorrected = record.wasManuallyCorrected
        evidence.algorithmVersion = record.algorithmVersion
        if existing == nil { context.insert(evidence) }
        try context.save()
    }
}
