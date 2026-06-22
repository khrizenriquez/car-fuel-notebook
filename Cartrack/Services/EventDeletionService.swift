import Foundation
import SwiftData

enum EventDeletionService {
    static func delete(vehicle: Vehicle, context: ModelContext) throws {
        let vehicleID = vehicle.id

        let fillEvents = try context.fetch(FetchDescriptor<FuelFillEvent>())
            .filter { $0.vehicle?.id == vehicleID }
        for fillEvent in fillEvents {
            try deleteAssets(eventID: fillEvent.id, ownerType: .fillUp, context: context)
            context.delete(fillEvent)
        }

        let snapshotEvents = try context.fetch(FetchDescriptor<SnapshotEvent>())
            .filter { $0.vehicle?.id == vehicleID }
        for snapshotEvent in snapshotEvents {
            try deleteAssets(eventID: snapshotEvent.id, ownerType: .snapshot, context: context)
            context.delete(snapshotEvent)
        }

        let adjustments = try context.fetch(FetchDescriptor<MonthlyManualAdjustment>())
            .filter { $0.vehicle?.id == vehicleID }
        for adjustment in adjustments {
            context.delete(adjustment)
        }

        context.delete(vehicle)
        try context.save()
    }

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
            try ImageStorageService.shared.deleteImage(at: asset.localPath)
            context.delete(asset)
        }
    }
}
