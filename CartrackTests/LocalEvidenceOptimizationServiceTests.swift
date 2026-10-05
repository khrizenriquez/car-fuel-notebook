import CryptoKit
import SwiftData
import UIKit
import XCTest
@testable import Cartrack

@MainActor
final class LocalEvidenceOptimizationServiceTests: XCTestCase {
    private enum InjectedFailure: Error { case beforeSave }

    func testConfirmedPhotoSwitchesBothReferencesOnlyAfterVerifiedCopy() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let report = try await LocalEvidenceOptimizationService.optimizePending(
            in: fixture.container, store: fixture.store
        )
        XCTAssertEqual(report.optimizedPhotos, 1)
        let context = ModelContext(fixture.container)
        let photo = try XCTUnwrap(context.fetch(FetchDescriptor<LocalPhotoAsset>()).first)
        let image = try XCTUnwrap(context.fetch(FetchDescriptor<ImageAsset>()).first)
        XCTAssertEqual(photo.optimizationStateRawValue, "optimized")
        let optimized = record(from: photo)
        XCTAssertEqual(image.localPath, try fixture.store.absolutePath(for: optimized))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.originalPath))
        XCTAssertLessThanOrEqual(max(photo.pixelWidth, photo.pixelHeight), 2_000)
        XCTAssertLessThanOrEqual(photo.byteCount, CapturePhotoStore.maxOptimizedByteCount)
        XCTAssertNotNil(try fixture.store.load(optimized).cgImage)
        XCTAssertEqual(photo.sha256.count, 64)
        let projectedMB = Double(photo.byteCount) * 10 * 52 / 1_000_000
        XCTAssertLessThanOrEqual(projectedMB, 250,
                                 "10 photos/week at fixture size should fit the local annual budget")
    }

    func testFailedDatabaseSaveRetainsOriginalAndCleansStagedFile() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let report = try await LocalEvidenceOptimizationService.optimizePending(
            in: fixture.container, store: fixture.store,
            beforeSave: { throw InjectedFailure.beforeSave }
        )
        XCTAssertEqual(report.optimizedPhotos, 0)
        XCTAssertEqual(report.retainedOriginals, 1)
        let context = ModelContext(fixture.container)
        let photo = try XCTUnwrap(context.fetch(FetchDescriptor<LocalPhotoAsset>()).first)
        let image = try XCTUnwrap(context.fetch(FetchDescriptor<ImageAsset>()).first)
        XCTAssertEqual(photo.optimizationStateRawValue, "original")
        XCTAssertEqual(image.localPath, fixture.originalPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.originalPath))
        XCTAssertEqual(try jpgCount(in: fixture.root), 1)
        let retry = try await LocalEvidenceOptimizationService.optimizePending(
            in: fixture.container, store: fixture.store
        )
        XCTAssertEqual(retry.optimizedPhotos, 1)
    }

    func testCorruptSourceDoesNotReplaceItsMetadataOrDeleteIt() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try Data("corrupt".utf8).write(to: URL(fileURLWithPath: fixture.originalPath))
        let report = try await LocalEvidenceOptimizationService.optimizePending(
            in: fixture.container, store: fixture.store
        )
        XCTAssertEqual(report.optimizedPhotos, 0)
        XCTAssertEqual(report.retainedOriginals, 1)
        let context = ModelContext(fixture.container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LocalPhotoAsset>()).first?.optimizationStateRawValue,
                       "original")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.originalPath))
    }

    func testStagingFailureRemovesReplacementAndKeepsOriginal() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let context = ModelContext(fixture.container)
        let photo = try XCTUnwrap(context.fetch(FetchDescriptor<LocalPhotoAsset>()).first)
        XCTAssertThrowsError(try fixture.store.optimizedCopy(of: record(from: photo), beforeReturn: {
            throw InjectedFailure.beforeSave
        }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.originalPath))
        XCTAssertEqual(try jpgCount(in: fixture.root), 1)
    }

    func testDiscardedUnconfirmedCaptureDeletesItsLocalOriginal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cartrack-discarded-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CapturePhotoStore(rootURL: root)
        let container = try CartrackModelContainer.make(isStoredInMemoryOnly: true)
        let sessionID = UUID()
        let photo = try store.save(texturedImage(), sessionID: sessionID, kind: .odometer)
        let originalPath = try store.absolutePath(for: photo)
        let context = ModelContext(container)
        context.insert(CaptureSessionRecord(
            id: sessionID, vehicleID: UUID(), kindRawValue: CaptureSessionKind.snapshot.rawValue,
            stateRawValue: CaptureSessionState.discarded.rawValue,
            createdAt: .now, updatedAt: .now, draftData: Data(), draftSHA256: "discarded"
        ))
        context.insert(LocalPhotoAsset(
            id: photo.id, sessionID: sessionID, eventID: nil,
            kindRawValue: photo.kind, localRelativePath: photo.localRelativePath,
            sha256: photo.sha256, pixelWidth: photo.pixelWidth,
            pixelHeight: photo.pixelHeight, byteCount: photo.byteCount,
            mimeType: photo.mimeType, capturedAt: photo.capturedAt,
            optimizationStateRawValue: "original", createdAt: photo.createdAt
        ))
        try context.save()

        _ = try await LocalEvidenceOptimizationService.optimizePending(in: container, store: store)

        let verification = ModelContext(container)
        XCTAssertTrue(try verification.fetch(FetchDescriptor<LocalPhotoAsset>()).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalPath))
    }

    private func makeFixture() throws -> (container: ModelContainer, store: CapturePhotoStore,
                                          root: URL, originalPath: String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cartrack-optimization-\(UUID().uuidString)")
        let store = CapturePhotoStore(rootURL: root)
        let container = try CartrackModelContainer.make(isStoredInMemoryOnly: true)
        let sessionID = UUID()
        let eventID = UUID()
        let source = texturedImage()
        let photo = try store.save(source, sessionID: sessionID, kind: .odometer)
        let originalPath = try store.absolutePath(for: photo)
        var draft = CaptureDraft()
        draft.photoIDs = [photo.id]
        draft.selectedPhotoIDsByKind = [CaptureImageKind.odometer.rawValue: photo.id]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(draft)
        let digest = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
        let context = ModelContext(container)
        let vehicle = Vehicle(name: "Z4", make: "BMW", modelName: "Z4", year: 2003)
        context.insert(vehicle)
        context.insert(SnapshotEvent(id: eventID, vehicle: vehicle, odometerKilometers: 1_000))
        context.insert(CaptureSessionRecord(
            id: sessionID, vehicleID: vehicle.id, kindRawValue: CaptureSessionKind.snapshot.rawValue,
            stateRawValue: CaptureSessionState.confirmed.rawValue,
            createdAt: .now, updatedAt: .now, confirmedEventID: eventID,
            draftData: encoded, draftSHA256: digest
        ))
        context.insert(LocalPhotoAsset(
            id: photo.id, sessionID: sessionID, eventID: eventID,
            kindRawValue: photo.kind, localRelativePath: photo.localRelativePath,
            sha256: photo.sha256, pixelWidth: photo.pixelWidth,
            pixelHeight: photo.pixelHeight, byteCount: photo.byteCount,
            mimeType: photo.mimeType, capturedAt: photo.capturedAt,
            optimizationStateRawValue: "original", createdAt: photo.createdAt
        ))
        context.insert(ImageAsset(eventID: eventID, ownerType: .snapshot,
                                  kind: .odometer, localPath: originalPath))
        try context.save()
        return (container, store, root, originalPath)
    }

    private func texturedImage() -> UIImage {
        let size = CGSize(width: 3_000, height: 1_500)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for row in 0..<50 {
                for column in 0..<100 {
                    UIColor(red: CGFloat((row * 17 + column * 7) % 255) / 255,
                            green: CGFloat((row * 3 + column * 29) % 255) / 255,
                            blue: CGFloat((row * 23 + column * 11) % 255) / 255,
                            alpha: 1).setFill()
                    context.fill(CGRect(x: column * 30, y: row * 30, width: 28, height: 28))
                }
            }
        }
    }

    private func record(from photo: LocalPhotoAsset) -> LocalPhotoRecord {
        LocalPhotoRecord(id: photo.id, sessionID: photo.sessionID, eventID: photo.eventID,
                         kind: photo.kindRawValue, localRelativePath: photo.localRelativePath,
                         sha256: photo.sha256, pixelWidth: photo.pixelWidth,
                         pixelHeight: photo.pixelHeight, byteCount: photo.byteCount,
                         mimeType: photo.mimeType, capturedAt: photo.capturedAt,
                         optimizationState: photo.optimizationStateRawValue,
                         createdAt: photo.createdAt)
    }

    private func jpgCount(in root: URL) throws -> Int {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        return enumerator.allObjects.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jpg" }.count
    }
}
