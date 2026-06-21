import Foundation
import SwiftData

enum EventDeletionService {
    static func delete(fillEvent: FuelFillEvent, context: ModelContext) throws {
        try deleteAssets(eventID: fillEvent.id, ownerType: .fillUp, context: context)
        context.delete(fillEvent)
        try context.save()
    }

    static func delete(snapshotEvent: SnapshotEvent, context: ModelContext) throws {
        try deleteAssets(eventID: snapshotEvent.id, ownerType: .snapshot, context: context)
        context.delete(snapshotEvent)
        try context.save()
    }

    private static func deleteAssets(eventID: UUID, ownerType: ImageOwnerKind, context: ModelContext) throws {
        let descriptor = FetchDescriptor<ImageAsset>(
            predicate: #Predicate { asset in
                asset.eventID == eventID && asset.ownerTypeRawValue == ownerType.rawValue
            }
        )
        for asset in try context.fetch(descriptor) {
            ImageStorageService.shared.deleteImage(at: asset.localPath)
            context.delete(asset)
        }
    }
}
