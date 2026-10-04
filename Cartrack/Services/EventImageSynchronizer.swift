import Foundation
import SwiftData
import UIKit

enum EventImageSynchronizer {
    /// Adds evidence for a new event. The caller removes returned files if its DB transaction fails.
    static func insertNewAssets(eventID: UUID, ownerType: ImageOwnerKind,
                                images: [CaptureImageKind: UIImage?],
                                context: ModelContext) throws -> [String] {
        var createdPaths: [String] = []
        do {
            for kind in images.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                guard let image = images[kind] ?? nil else { continue }
                let path = try ImageStorageService.shared.saveImage(
                    image, preferredName: "\(kind.rawValue)-\(UUID().uuidString)"
                )
                createdPaths.append(path)
                context.insert(ImageAsset(eventID: eventID, ownerType: ownerType,
                                          kind: kind, localPath: path))
            }
            return createdPaths
        } catch {
            for path in createdPaths { try? ImageStorageService.shared.deleteImage(at: path) }
            throw error
        }
    }

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
                try ImageStorageService.shared.deleteImage(at: existing.localPath)
                context.delete(existing)
            }
            guard let image = images[kind] ?? nil else { continue }
            let path = try ImageStorageService.shared.saveImage(image, preferredName: "\(kind.rawValue)-\(UUID().uuidString)")
            let asset = ImageAsset(eventID: eventID, ownerType: ownerType, kind: kind, localPath: path)
            context.insert(asset)
        }
    }
}
