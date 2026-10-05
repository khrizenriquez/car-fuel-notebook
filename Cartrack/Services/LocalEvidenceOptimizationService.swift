import Foundation
import SwiftData

struct LocalEvidenceOptimizationReport: Equatable {
    var optimizedPhotos = 0
    var removedOrphanFiles = 0
    var retainedOriginals = 0
}

@MainActor
enum LocalEvidenceOptimizationService {
    private static var isRunning = false

    /// A failed session leaves all original references and bytes untouched. Another launch can retry it.
    static func optimizePending(in container: ModelContainer,
                                store: CapturePhotoStore = CapturePhotoStore(),
                                beforeSave: (() throws -> Void)? = nil) async throws -> LocalEvidenceOptimizationReport {
        guard !isRunning else { return LocalEvidenceOptimizationReport() }
        isRunning = true
        defer { isRunning = false }
        try cleanupDiscardedPhotos(in: container, store: store)
        let scan = ModelContext(container)
        let sessions = try scan.fetch(FetchDescriptor<CaptureSessionRecord>())
            .filter { $0.stateRawValue == CaptureSessionState.confirmed.rawValue }
        var report = LocalEvidenceOptimizationReport()
        let repository = SwiftDataCaptureSessionRepository(container: container)
        for row in sessions {
            guard let session = try await repository.find(id: row.id),
                  let eventID = session.confirmedEventID else { continue }
            do {
                report.optimizedPhotos += try optimizeSession(
                    sessionID: row.id, eventID: eventID, draft: session.draft,
                    in: container, store: store, beforeSave: beforeSave
                )
            } catch {
                report.retainedOriginals += try scan.fetch(FetchDescriptor<LocalPhotoAsset>())
                    .filter { $0.sessionID == row.id && $0.optimizationStateRawValue != "optimized" }.count
            }
        }
        report.removedOrphanFiles = try cleanupOrphans(in: container, store: store)
        return report
    }

    /// Discarded, unconfirmed captures have no event asset that needs to survive. Delete
    /// their database rows first; only then remove the explicitly app-owned local bytes.
    private static func cleanupDiscardedPhotos(in container: ModelContainer,
                                               store: CapturePhotoStore) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let discardedIDs = Set(try context.fetch(FetchDescriptor<CaptureSessionRecord>())
            .filter { $0.stateRawValue == CaptureSessionState.discarded.rawValue }.map(\.id))
        guard !discardedIDs.isEmpty else { return }
        let photos = try context.fetch(FetchDescriptor<LocalPhotoAsset>())
            .filter { $0.sessionID.map(discardedIDs.contains) == true && $0.eventID == nil }
        guard !photos.isEmpty else { return }
        let retiredPaths = photos.compactMap { try? store.absolutePath(for: record(for: $0)) }
        for photo in photos { context.delete(photo) }
        try context.save()
        for path in retiredPaths {
            // `absolutePath(for:)` has already constrained this to the store's UUID-based
            // CaptureSessions tree, so this cannot reach arbitrary user files.
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private static func optimizeSession(sessionID: UUID, eventID: UUID, draft: CaptureDraft,
                                        in container: ModelContainer, store: CapturePhotoStore,
                                        beforeSave: (() throws -> Void)?) throws -> Int {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let photos = try context.fetch(FetchDescriptor<LocalPhotoAsset>())
            .filter { $0.sessionID == sessionID && $0.eventID == eventID && $0.optimizationStateRawValue != "optimized" }
        guard !photos.isEmpty else { return 0 }
        let allPhotos = try context.fetch(FetchDescriptor<LocalPhotoAsset>())
            .filter { $0.sessionID == sessionID && $0.eventID == eventID }
        let selectedIDs: [String: UUID] = draft.selectedPhotoIDsByKind ?? Dictionary(
            uniqueKeysWithValues: Dictionary(grouping: allPhotos, by: \.kindRawValue)
                .compactMap { kind, candidates in
                    candidates.max(by: { $0.createdAt < $1.createdAt }).map { (kind, $0.id) }
                }
        )
        let eventImages = try context.fetch(FetchDescriptor<ImageAsset>())
            .filter { $0.eventID == eventID }
        var staged: [LocalPhotoRecord] = []
        var retiredPaths: [String] = []
        do {
            for photo in photos {
                let original = record(for: photo)
                retiredPaths.append(try store.absolutePath(for: original))
                let optimized = try store.optimizedCopy(of: original)
                staged.append(optimized)
                photo.localRelativePath = optimized.localRelativePath
                photo.sha256 = optimized.sha256
                photo.pixelWidth = optimized.pixelWidth
                photo.pixelHeight = optimized.pixelHeight
                photo.byteCount = optimized.byteCount
                photo.optimizationStateRawValue = "optimized"
                if selectedIDs[photo.kindRawValue] == photo.id {
                    for image in eventImages where image.kindRawValue == photo.kindRawValue {
                        retiredPaths.append(image.localPath)
                        image.localPath = try store.absolutePath(for: optimized)
                    }
                }
            }
            try beforeSave?()
            try context.save()
            EventDeletionService.retire(retiredPaths, in: context)
            return photos.count
        } catch {
            context.rollback()
            for optimized in staged { try? store.remove(optimized) }
            throw error
        }
    }

    /// Deletes only unreferenced JPEG files under the app-owned evidence root.
    static func cleanupOrphans(in container: ModelContainer,
                               store: CapturePhotoStore = CapturePhotoStore(),
                               minimumAge: TimeInterval = 3_600) throws -> Int {
        let context = ModelContext(container)
        let photoPaths = try context.fetch(FetchDescriptor<LocalPhotoAsset>())
            .compactMap { try? store.absolutePath(for: record(for: $0)) }
        let imagePaths = try context.fetch(FetchDescriptor<ImageAsset>()).map(\.localPath)
        let referenced = Set(photoPaths + imagePaths)
        let root = try store.evidenceRootURL()
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey]
        ) else {
            return 0
        }
        var removed = 0
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "jpg", !referenced.contains(url.path),
                  url.path.hasPrefix(root.path + "/") else { continue }
            let modifiedAt = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .now
            guard Date.now.timeIntervalSince(modifiedAt) >= minimumAge else { continue }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            let parts = relative.split(separator: "/")
            let isOwnedSessionPhoto = parts.count == 3 && parts[0] == "CaptureSessions"
                && UUID(uuidString: String(parts[1])) != nil
                && UUID(uuidString: String(parts[2].dropLast(4))) != nil
            let stem = url.deletingPathExtension().lastPathComponent
            let isOwnedEventPhoto = parts.count == 1 && (
                UUID(uuidString: stem) != nil || CaptureImageKind.allCases.contains { kind in
                    let prefix = kind.rawValue + "-"
                    return stem.hasPrefix(prefix)
                        && UUID(uuidString: String(stem.dropFirst(prefix.count))) != nil
                }
            )
            guard isOwnedSessionPhoto || isOwnedEventPhoto else { continue }
            try FileManager.default.removeItem(at: url)
            removed += 1
        }
        return removed
    }

    private static func record(for photo: LocalPhotoAsset) -> LocalPhotoRecord {
        LocalPhotoRecord(id: photo.id, sessionID: photo.sessionID, eventID: photo.eventID,
                         kind: photo.kindRawValue, localRelativePath: photo.localRelativePath,
                         sha256: photo.sha256, pixelWidth: photo.pixelWidth,
                         pixelHeight: photo.pixelHeight, byteCount: photo.byteCount,
                         mimeType: photo.mimeType, capturedAt: photo.capturedAt,
                         optimizationState: photo.optimizationStateRawValue,
                         createdAt: photo.createdAt)
    }
}
