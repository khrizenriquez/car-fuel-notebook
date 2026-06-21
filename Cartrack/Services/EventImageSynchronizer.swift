import Foundation
import SwiftData
import UIKit

enum EventImageSynchronizer {
    static func replaceAssets(
        for fillEvent: FuelFillEvent,
        images: [CaptureImageKind: UIImage?],
        removedKinds: Set<CaptureImageKind> = [],
        context: ModelContext
    ) throws {
        try replace(eventID: fillEvent.id, ownerType: .fillUp, images: images, removedKinds: removedKinds, context: context)
    }

    static func replaceAssets(
        for snapshotEvent: SnapshotEvent,
        images: [CaptureImageKind: UIImage?],
        removedKinds: Set<CaptureImageKind> = [],
        context: ModelContext
    ) throws {
        try replace(eventID: snapshotEvent.id, ownerType: .snapshot, images: images, removedKinds: removedKinds, context: context)
    }

    private static func replace(
        eventID: UUID,
        ownerType: ImageOwnerKind,
        images: [CaptureImageKind: UIImage?],
        removedKinds: Set<CaptureImageKind>,
        context: ModelContext
    ) throws {
        for kind in Set(images.keys).union(removedKinds) {
            let descriptor = FetchDescriptor<ImageAsset>(
                predicate: #Predicate { asset in
                    asset.eventID == eventID &&
                    asset.ownerTypeRawValue == ownerType.rawValue &&
                    asset.kindRawValue == kind.rawValue
                }
            )
            if let existing = try context.fetch(descriptor).first {
                ImageStorageService.shared.deleteImage(at: existing.localPath)
                context.delete(existing)
            }
            guard let image = images[kind] ?? nil else { continue }
            let path = try ImageStorageService.shared.saveImage(image, preferredName: "\(kind.rawValue)-\(UUID().uuidString)")
            let asset = ImageAsset(eventID: eventID, ownerType: ownerType, kind: kind, localPath: path)
            context.insert(asset)
        }
    }
}
