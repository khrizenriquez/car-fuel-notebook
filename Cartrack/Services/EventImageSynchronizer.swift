import Foundation
import SwiftData
import UIKit

struct ImageReplacementPlan {
    let createdPaths: [String]
    let retiredPaths: [String]

    func rollback() {
        for path in createdPaths { try? ImageStorageService.shared.deleteImage(at: path) }
    }

    /// The database has committed. A still-referenced OCR source must not be removed.
    func finish(in context: ModelContext) {
        guard let localPhotos = try? context.fetch(FetchDescriptor<LocalPhotoAsset>()),
              let eventImages = try? context.fetch(FetchDescriptor<ImageAsset>()) else { return }
        let protectedPaths = Set(localPhotos.compactMap { photo -> String? in
            let record = LocalPhotoRecord(
                id: photo.id, sessionID: photo.sessionID, eventID: photo.eventID,
                kind: photo.kindRawValue, localRelativePath: photo.localRelativePath,
                sha256: photo.sha256, pixelWidth: photo.pixelWidth,
                pixelHeight: photo.pixelHeight, byteCount: photo.byteCount,
                mimeType: photo.mimeType, capturedAt: photo.capturedAt,
                optimizationState: photo.optimizationStateRawValue, createdAt: photo.createdAt
            )
            return try? CapturePhotoStore().absolutePath(for: record)
        } + eventImages.map(\.localPath))
        for path in Set(retiredPaths) where !protectedPaths.contains(path) {
            try? ImageStorageService.shared.deleteImage(at: path)
        }
    }
}

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

    static func prepareReplacement(
        for fillEvent: FuelFillEvent,
        images: [CaptureImageKind: UIImage?],
        removedKinds: Set<CaptureImageKind> = [],
        context: ModelContext
    ) throws -> ImageReplacementPlan {
        try prepare(eventID: fillEvent.id, ownerType: .fillUp, images: images,
                    removedKinds: removedKinds, context: context)
    }

    static func prepareReplacement(
        for snapshotEvent: SnapshotEvent,
        images: [CaptureImageKind: UIImage?],
        removedKinds: Set<CaptureImageKind> = [],
        context: ModelContext
    ) throws -> ImageReplacementPlan {
        try prepare(eventID: snapshotEvent.id, ownerType: .snapshot, images: images,
                    removedKinds: removedKinds, context: context)
    }

    private static func prepare(
        eventID: UUID,
        ownerType: ImageOwnerKind,
        images: [CaptureImageKind: UIImage?],
        removedKinds: Set<CaptureImageKind>,
        context: ModelContext
    ) throws -> ImageReplacementPlan {
        var createdPaths: [String] = []
        var retiredPaths: [String] = []
        do {
        for kind in Set(images.keys).union(removedKinds).sorted(by: { $0.rawValue < $1.rawValue }) {
            let descriptor = FetchDescriptor<ImageAsset>(
                predicate: #Predicate { asset in
                    asset.eventID == eventID &&
                    asset.ownerTypeRawValue == ownerType.rawValue &&
                    asset.kindRawValue == kind.rawValue
                }
            )
            if let existing = try context.fetch(descriptor).first {
                retiredPaths.append(existing.localPath)
                context.delete(existing)
            }
            guard let image = images[kind] ?? nil else { continue }
            let path = try ImageStorageService.shared.saveImage(image, preferredName: "\(kind.rawValue)-\(UUID().uuidString)")
            createdPaths.append(path)
            let asset = ImageAsset(eventID: eventID, ownerType: ownerType, kind: kind, localPath: path)
            context.insert(asset)
        }
        return ImageReplacementPlan(createdPaths: createdPaths, retiredPaths: retiredPaths)
        } catch {
            for path in createdPaths { try? ImageStorageService.shared.deleteImage(at: path) }
            throw error
        }
    }
}
