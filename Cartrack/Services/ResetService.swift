import Foundation
import SwiftData

enum ResetService {
    static func resetAll(context: ModelContext) throws {
        for asset in try context.fetch(FetchDescriptor<ImageAsset>()) {
            ImageStorageService.shared.deleteImage(at: asset.localPath)
            context.delete(asset)
        }

        for adjustment in try context.fetch(FetchDescriptor<MonthlyManualAdjustment>()) {
            context.delete(adjustment)
        }
        for snapshot in try context.fetch(FetchDescriptor<SnapshotEvent>()) {
            context.delete(snapshot)
        }
        for fill in try context.fetch(FetchDescriptor<FuelFillEvent>()) {
            context.delete(fill)
        }
        for vehicle in try context.fetch(FetchDescriptor<Vehicle>()) {
            context.delete(vehicle)
        }

        try context.save()
        try ImageStorageService.shared.clearAllImages()
    }
}
