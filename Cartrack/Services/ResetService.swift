import Foundation
import SwiftData

enum ResetService {
    static func resetData(for vehicle: Vehicle, context: ModelContext) throws {
        let vehicleID = vehicle.id
        var retiredPaths: [String] = []

        let fills = try context.fetch(FetchDescriptor<FuelFillEvent>())
            .filter { $0.vehicle?.id == vehicleID }
        for fill in fills {
            retiredPaths += try EventDeletionService.prepareDeleteAssets(
                eventID: fill.id, ownerType: .fillUp, context: context
            )
            try SyncMetadataMaintainer.remove(ownerID: fill.id, in: context)
            context.delete(fill)
        }

        let snapshots = try context.fetch(FetchDescriptor<SnapshotEvent>())
            .filter { $0.vehicle?.id == vehicleID }
        for snapshot in snapshots {
            retiredPaths += try EventDeletionService.prepareDeleteAssets(
                eventID: snapshot.id, ownerType: .snapshot, context: context
            )
            try SyncMetadataMaintainer.remove(ownerID: snapshot.id, in: context)
            context.delete(snapshot)
        }

        let adjustments = try context.fetch(FetchDescriptor<MonthlyManualAdjustment>())
            .filter { $0.vehicle?.id == vehicleID }
        for adjustment in adjustments {
            context.delete(adjustment)
        }

        try context.save()
        EventDeletionService.retire(retiredPaths, in: context)
    }
}
