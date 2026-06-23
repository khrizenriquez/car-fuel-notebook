import Foundation
import SwiftData

enum ResetService {
    static func resetData(for vehicle: Vehicle, context: ModelContext) throws {
        let vehicleID = vehicle.id

        let fills = try context.fetch(FetchDescriptor<FuelFillEvent>())
            .filter { $0.vehicle?.id == vehicleID }
        for fill in fills {
            try deleteAssets(eventID: fill.id, ownerType: .fillUp, context: context)
            context.delete(fill)
        }

        let snapshots = try context.fetch(FetchDescriptor<SnapshotEvent>())
            .filter { $0.vehicle?.id == vehicleID }
        for snapshot in snapshots {
            try deleteAssets(eventID: snapshot.id, ownerType: .snapshot, context: context)
            context.delete(snapshot)
        }

        let adjustments = try context.fetch(FetchDescriptor<MonthlyManualAdjustment>())
            .filter { $0.vehicle?.id == vehicleID }
        for adjustment in adjustments {
            context.delete(adjustment)
        }

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
