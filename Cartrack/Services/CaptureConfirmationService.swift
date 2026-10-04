import SwiftData
import UIKit

enum CaptureConfirmationError: Error {
    case vehicleNotFound
}

@MainActor
enum CaptureConfirmationService {
    /// Creates the event, local image indexes, sync metadata and confirmed session in one DB save.
    /// Image files are staged first and removed if that save fails.
    static func confirm(container: ModelContainer, sessionID: UUID,
                        expectedRevision: Int64, vehicleID: UUID,
                        kind: CaptureSessionKind, finalDraft: CaptureDraft,
                        images: [CaptureImageKind: UIImage?],
                        buildEvent: (Vehicle, ModelContext) throws -> UUID,
                        beforeSave: (() throws -> Void)? = nil) throws -> UUID {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        guard let vehicle = try context.fetch(FetchDescriptor<Vehicle>())
            .first(where: { $0.id == vehicleID }) else {
            throw CaptureConfirmationError.vehicleNotFound
        }
        var createdPaths: [String] = []
        do {
            let eventID = try buildEvent(vehicle, context)
            let ownerType: ImageOwnerKind = kind == .fillUp ? .fillUp : .snapshot
            createdPaths = try EventImageSynchronizer.insertNewAssets(
                eventID: eventID, ownerType: ownerType, images: images, context: context
            )
            try SwiftDataCaptureSessionRepository.prepareConfirmation(
                id: sessionID, expectedRevision: expectedRevision,
                vehicleID: vehicleID, kind: kind, eventID: eventID,
                finalDraft: finalDraft, in: context
            )
            try beforeSave?()
            try context.save()
            return eventID
        } catch {
            context.rollback()
            for path in createdPaths { try? ImageStorageService.shared.deleteImage(at: path) }
            throw error
        }
    }
}
