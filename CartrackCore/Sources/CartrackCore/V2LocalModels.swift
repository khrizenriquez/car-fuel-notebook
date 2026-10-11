import Foundation
import SwiftData

// These v2-only models are additive. The five physical v1 entities stay unchanged so the
// legacy reader in CartrackModelContainer can still open a pre-v2 store without rewriting it.
@Model
final class SyncMetadataRecord {
    @Attribute(.unique) var ownerID: UUID
    var ownerKindRawValue: String
    var schemaVersion: Int
    var revision: Int64
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var originDeviceID: UUID?
    var lastSyncedRevision: Int64?

    init(
        ownerID: UUID,
        ownerKindRawValue: String,
        schemaVersion: Int = 2,
        revision: Int64 = 1,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        originDeviceID: UUID? = nil,
        lastSyncedRevision: Int64? = nil
    ) {
        self.ownerID = ownerID
        self.ownerKindRawValue = ownerKindRawValue
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceID = originDeviceID
        self.lastSyncedRevision = lastSyncedRevision
    }
}

@Model
final class V2RecordExtras {
    @Attribute(.unique) var ownerID: UUID
    var reserveThresholdRatioDecimal: String?
    var currencyCode: String?
    var sourceSessionID: UUID?

    init(ownerID: UUID, reserveThresholdRatioDecimal: String? = nil,
         currencyCode: String? = nil, sourceSessionID: UUID? = nil) {
        self.ownerID = ownerID
        self.reserveThresholdRatioDecimal = reserveThresholdRatioDecimal
        self.currencyCode = currencyCode
        self.sourceSessionID = sourceSessionID
    }
}

@Model
final class LocalPhotoAsset {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID?
    var eventID: UUID?
    var kindRawValue: String
    var localRelativePath: String
    var sha256: String
    var pixelWidth: Int
    var pixelHeight: Int
    var byteCount: Int
    var mimeType: String
    var capturedAt: Date?
    var optimizationStateRawValue: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sessionID: UUID? = nil,
        eventID: UUID? = nil,
        kindRawValue: String,
        localRelativePath: String,
        sha256: String,
        pixelWidth: Int,
        pixelHeight: Int,
        byteCount: Int,
        mimeType: String,
        capturedAt: Date? = nil,
        optimizationStateRawValue: String = "original",
        createdAt: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.eventID = eventID
        self.kindRawValue = kindRawValue
        self.localRelativePath = localRelativePath
        self.sha256 = sha256
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteCount = byteCount
        self.mimeType = mimeType
        self.capturedAt = capturedAt
        self.optimizationStateRawValue = optimizationStateRawValue
        self.createdAt = createdAt
    }
}

@Model
final class OCRFieldEvidence {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var ownerEventID: UUID?
    var fieldRawValue: String
    var rawText: String?
    var normalizedValue: String?
    var unit: String?
    var confidenceDecimal: String
    var confidenceBandRawValue: String
    var sourcePhotoID: UUID?
    var validationCodes: [String]
    var wasManuallyCorrected: Bool
    var algorithmVersion: String

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        ownerEventID: UUID? = nil,
        fieldRawValue: String,
        rawText: String? = nil,
        normalizedValue: String? = nil,
        unit: String? = nil,
        confidenceDecimal: String,
        confidenceBandRawValue: String,
        sourcePhotoID: UUID? = nil,
        validationCodes: [String] = [],
        wasManuallyCorrected: Bool = false,
        algorithmVersion: String
    ) {
        self.id = id
        self.sessionID = sessionID
        self.ownerEventID = ownerEventID
        self.fieldRawValue = fieldRawValue
        self.rawText = rawText
        self.normalizedValue = normalizedValue
        self.unit = unit
        self.confidenceDecimal = confidenceDecimal
        self.confidenceBandRawValue = confidenceBandRawValue
        self.sourcePhotoID = sourcePhotoID
        self.validationCodes = validationCodes
        self.wasManuallyCorrected = wasManuallyCorrected
        self.algorithmVersion = algorithmVersion
    }
}

enum SyncMetadataMaintainer {
    static func recordChange(
        ownerID: UUID, kind: String, createdAt: Date, updatedAt: Date,
        in context: ModelContext
    ) throws {
        if let stored = try context.fetch(FetchDescriptor<SyncMetadataRecord>())
            .first(where: { $0.ownerID == ownerID }) {
            guard stored.ownerKindRawValue == kind else { throw RepositoryError.conflict }
            stored.revision += 1
            stored.updatedAt = updatedAt
            stored.deletedAt = nil
        } else {
            context.insert(SyncMetadataRecord(ownerID: ownerID, ownerKindRawValue: kind,
                                              createdAt: createdAt, updatedAt: updatedAt))
        }
    }

    static func remove(ownerID: UUID, in context: ModelContext) throws {
        for metadata in try context.fetch(FetchDescriptor<SyncMetadataRecord>()) where metadata.ownerID == ownerID {
            context.delete(metadata)
        }
        for extras in try context.fetch(FetchDescriptor<V2RecordExtras>()) where extras.ownerID == ownerID {
            context.delete(extras)
        }
    }
}
