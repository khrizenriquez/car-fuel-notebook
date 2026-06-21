import Foundation
import SwiftData

enum CartrackModelContainer {
    static func make(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        if !isStoredInMemoryOnly {
            let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try FileManager.default.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
        }

        let schema = Schema([
            Vehicle.self,
            FuelFillEvent.self,
            SnapshotEvent.self,
            MonthlyManualAdjustment.self,
            ImageAsset.self,
        ])
        let configuration = ModelConfiguration(
            "CartrackData",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
