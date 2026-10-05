import Foundation
import SwiftData

enum EventDeletionService {
    static func delete(vehicle: Vehicle, context: ModelContext) throws {
        let vehicleID = vehicle.id
        var retiredPaths: [String] = []

        let fillEvents = try context.fetch(FetchDescriptor<FuelFillEvent>())
            .filter { $0.vehicle?.id == vehicleID }
        for fillEvent in fillEvents {
            retiredPaths += try prepareDeleteAssets(eventID: fillEvent.id, ownerType: .fillUp, context: context)
            try SyncMetadataMaintainer.remove(ownerID: fillEvent.id, in: context)
            context.delete(fillEvent)
        }

        let snapshotEvents = try context.fetch(FetchDescriptor<SnapshotEvent>())
            .filter { $0.vehicle?.id == vehicleID }
        for snapshotEvent in snapshotEvents {
            retiredPaths += try prepareDeleteAssets(eventID: snapshotEvent.id, ownerType: .snapshot, context: context)
            try SyncMetadataMaintainer.remove(ownerID: snapshotEvent.id, in: context)
            context.delete(snapshotEvent)
        }

        let adjustments = try context.fetch(FetchDescriptor<MonthlyManualAdjustment>())
            .filter { $0.vehicle?.id == vehicleID }
        for adjustment in adjustments {
            context.delete(adjustment)
        }

        try SyncMetadataMaintainer.remove(ownerID: vehicleID, in: context)
        context.delete(vehicle)
        try context.save()
        retire(retiredPaths, in: context)
    }

    static func delete(fillEvent: FuelFillEvent, context: ModelContext) throws {
        let retiredPaths = try prepareDeleteAssets(eventID: fillEvent.id, ownerType: .fillUp, context: context)
        try SyncMetadataMaintainer.remove(ownerID: fillEvent.id, in: context)
        context.delete(fillEvent)
        try context.save()
        retire(retiredPaths, in: context)
    }

    static func delete(snapshotEvent: SnapshotEvent, context: ModelContext) throws {
        let retiredPaths = try prepareDeleteAssets(eventID: snapshotEvent.id, ownerType: .snapshot, context: context)
        try SyncMetadataMaintainer.remove(ownerID: snapshotEvent.id, in: context)
        context.delete(snapshotEvent)
        try context.save()
        retire(retiredPaths, in: context)
    }

    static func prepareDeleteAssets(eventID: UUID, ownerType: ImageOwnerKind,
                                    context: ModelContext) throws -> [String] {
        let descriptor = FetchDescriptor<ImageAsset>(
            predicate: #Predicate { asset in
                asset.eventID == eventID && asset.ownerTypeRawValue == ownerType.rawValue
            }
        )
        var retiredPaths: [String] = []
        for asset in try context.fetch(descriptor) {
            retiredPaths.append(asset.localPath)
            context.delete(asset)
        }
        for photo in try context.fetch(FetchDescriptor<LocalPhotoAsset>()) where photo.eventID == eventID {
            let record = LocalPhotoRecord(
                id: photo.id, sessionID: photo.sessionID, eventID: photo.eventID,
                kind: photo.kindRawValue, localRelativePath: photo.localRelativePath,
                sha256: photo.sha256, pixelWidth: photo.pixelWidth,
                pixelHeight: photo.pixelHeight, byteCount: photo.byteCount,
                mimeType: photo.mimeType, capturedAt: photo.capturedAt,
                optimizationState: photo.optimizationStateRawValue, createdAt: photo.createdAt
            )
            if let path = try? CapturePhotoStore().absolutePath(for: record) {
                retiredPaths.append(path)
            }
            context.delete(photo)
        }
        for evidence in try context.fetch(FetchDescriptor<OCRFieldEvidence>()) where evidence.ownerEventID == eventID {
            context.delete(evidence)
        }
        for session in try context.fetch(FetchDescriptor<CaptureSessionRecord>()) where session.confirmedEventID == eventID {
            context.delete(session)
        }
        return retiredPaths
    }

    static func retire(_ paths: [String], in context: ModelContext) {
        guard let photos = try? context.fetch(FetchDescriptor<LocalPhotoAsset>()),
              let images = try? context.fetch(FetchDescriptor<ImageAsset>()) else { return }
        let referenced = Set(images.map(\.localPath) + photos.compactMap { photo -> String? in
            let record = LocalPhotoRecord(
                id: photo.id, sessionID: photo.sessionID, eventID: photo.eventID,
                kind: photo.kindRawValue, localRelativePath: photo.localRelativePath,
                sha256: photo.sha256, pixelWidth: photo.pixelWidth,
                pixelHeight: photo.pixelHeight, byteCount: photo.byteCount,
                mimeType: photo.mimeType, capturedAt: photo.capturedAt,
                optimizationState: photo.optimizationStateRawValue, createdAt: photo.createdAt
            )
            return try? CapturePhotoStore().absolutePath(for: record)
        })
        for path in Set(paths) where !referenced.contains(path) {
            try? ImageStorageService.shared.deleteImage(at: path)
        }
    }
}
