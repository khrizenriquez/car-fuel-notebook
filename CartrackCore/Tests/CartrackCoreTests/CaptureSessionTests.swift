import Foundation
import SwiftData
import XCTest
@testable import CartrackCore

final class CaptureSessionStateTests: XCTestCase {
    func testStateMachineAllowsOnlyReviewedConfirmationAndExplicitDiscard() {
        XCTAssertTrue(CaptureSessionStateMachine.allows(from: .draft, to: .analyzing))
        XCTAssertTrue(CaptureSessionStateMachine.allows(from: .analyzing, to: .review))
        XCTAssertTrue(CaptureSessionStateMachine.allows(from: .review, to: .confirmed))
        XCTAssertTrue(CaptureSessionStateMachine.allows(from: .failedRecoverable, to: .analyzing))
        XCTAssertFalse(CaptureSessionStateMachine.allows(from: .draft, to: .confirmed))
        XCTAssertFalse(CaptureSessionStateMachine.allows(from: .confirmed, to: .draft))
        XCTAssertFalse(CaptureSessionStateMachine.allows(from: .discarded, to: .review))
        XCTAssertFalse(CaptureSessionState.analyzing.isResumable)
        XCTAssertTrue(CaptureSessionState.review.isResumable)
    }

    func testDraftRejectsSnapshotFinancialFieldsAndDuplicatePhotoIDs() throws {
        var draft = CaptureDraft()
        draft.totalCost = 100
        XCTAssertThrowsError(try draft.validate(for: .snapshot))
        XCTAssertNoThrow(try draft.validate(for: .fillUp))
        draft.totalCost = nil
        let photoID = UUID()
        draft.photoIDs = [photoID, photoID]
        XCTAssertThrowsError(try draft.validate(for: .snapshot))
        draft.photoIDs = [photoID]
        XCTAssertNoThrow(try draft.validate(for: .snapshot))
    }
}

@MainActor
final class CaptureSessionPersistenceTests: XCTestCase {
    func testExistingT06StoreOpensWithCaptureSessionsWithoutLosingLocalEvidence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CartrackT07UpgradeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storesDirectory = directory.appendingPathComponent("CartrackV2/Stores", isDirectory: true)
        try FileManager.default.createDirectory(at: storesDirectory, withIntermediateDirectories: true)
        let storeName = "\(UUID().uuidString).store"
        let storeURL = storesDirectory.appendingPathComponent(storeName)
        let oldSchema = Schema(CartrackV1Schema.models + [LocalStoreVersion.self,
                         SyncMetadataRecord.self, V2RecordExtras.self,
                         LocalPhotoAsset.self, OCRFieldEvidence.self],
                         version: Schema.Version(2, 0, 1))
        let oldConfiguration = ModelConfiguration("CartrackDataV2", schema: oldSchema,
                                                  url: storeURL, allowsSave: true,
                                                  cloudKitDatabase: .none)
        let oldContainer = try ModelContainer(for: oldSchema, configurations: [oldConfiguration])
        let oldContext = ModelContext(oldContainer)
        let vehicle = Vehicle(name: "Existing Z4", make: "BMW", modelName: "Z4", year: 2003)
        let sessionID = UUID()
        oldContext.insert(vehicle)
        oldContext.insert(LocalStoreVersion(sourceFingerprint: "t06-fingerprint"))
        oldContext.insert(OCRFieldEvidence(sessionID: sessionID, fieldRawValue: "odometer",
                                           rawText: "108796", confidenceDecimal: "0.9",
                                           confidenceBandRawValue: "high", algorithmVersion: "t06"))
        try oldContext.save()
        let pointer: [String: Any] = ["schemaVersion": 2, "storeName": storeName,
                                      "sourceFingerprint": "t06-fingerprint"]
        let pointerURL = directory.appendingPathComponent("CartrackV2/active-store.json")
        try JSONSerialization.data(withJSONObject: pointer).write(to: pointerURL, options: .atomic)

        let upgraded = try CartrackModelContainer.make(applicationSupportURL: directory,
                                                        legacyStoreURL: directory.appendingPathComponent("unused-v1.store"))
        let context = ModelContext(upgraded)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Vehicle>()).first?.id, vehicle.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<OCRFieldEvidence>()).first?.sessionID, sessionID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CaptureSessionRecord>()).count, 0)
    }

    func testDraftAndReviewSurviveRelaunchWithCanonicalValuesAndPhotoIDs() async throws {
        try await withPersistentStore { container, support, legacyURL in
            let vehicleID = UUID()
            let context = ModelContext(container)
            context.insert(Vehicle(id: vehicleID, name: "Z4", make: "BMW", modelName: "Z4", year: 2003))
            try context.save()
            let first = SwiftDataCaptureSessionRepository(container: container)
            let photoID = UUID()
            var draft = CaptureDraft()
            draft.odometerKilometers = Decimal(string: "175012.9")
            draft.tripKilometers = Decimal(string: "945.1")
            draft.photoIDs = [photoID]
            let created = try await first.create(kind: .snapshot, vehicleID: vehicleID, draft: draft)
            XCTAssertEqual(created.state, .draft)

            let reopenedContainer = try CartrackModelContainer.make(applicationSupportURL: support,
                                                                     legacyStoreURL: legacyURL)
            _ = try SwiftDataCaptureSessionRepository.recoverOnLaunch(in: reopenedContainer)
            let reopened = SwiftDataCaptureSessionRepository(container: reopenedContainer)
            let resumedResult = try await reopened.find(id: created.id)
            let resumed = try XCTUnwrap(resumedResult)
            XCTAssertEqual(resumed.draft, draft)
            XCTAssertEqual(resumed.draft.photoIDs, [photoID])
            XCTAssertEqual(resumed.state, .draft)

            let analyzing = try await reopened.transition(id: resumed.id, expectedRevision: resumed.revision,
                                                            to: .analyzing, errorCode: nil,
                                                            confirmedEventID: nil)
            let review = try await reopened.transition(id: analyzing.id, expectedRevision: analyzing.revision,
                                                         to: .review, errorCode: nil,
                                                         confirmedEventID: nil)
            let thirdContainer = try CartrackModelContainer.make(applicationSupportURL: support,
                                                                  legacyStoreURL: legacyURL)
            _ = try SwiftDataCaptureSessionRepository.recoverOnLaunch(in: thirdContainer)
            let reviewRepository = SwiftDataCaptureSessionRepository(container: thirdContainer)
            let reviewResult = try await reviewRepository.find(id: review.id)
            let reviewAfterRelaunch = try XCTUnwrap(reviewResult)
            XCTAssertEqual(reviewAfterRelaunch.state, .review)
            XCTAssertEqual(reviewAfterRelaunch.draft, draft)
            let reviewIndex = try await reviewRepository.resumable()
            XCTAssertEqual(reviewIndex.sessions.map(\.id), [review.id])
        }
    }

    func testAnalyzingRelaunchBecomesRecoverableAndCanRetry() async throws {
        try await withPersistentStore { container, support, legacyURL in
            let repository = SwiftDataCaptureSessionRepository(container: container)
            var draft = CaptureDraft()
            draft.volumeGallons = 11
            draft.totalCost = 473
            let created = try await repository.create(kind: .fillUp, vehicleID: nil, draft: draft)
            let analyzing = try await repository.transition(id: created.id, expectedRevision: created.revision,
                                                              to: .analyzing, errorCode: nil,
                                                              confirmedEventID: nil)

            let reopenedContainer = try CartrackModelContainer.make(applicationSupportURL: support,
                                                                     legacyStoreURL: legacyURL)
            XCTAssertEqual(try SwiftDataCaptureSessionRepository.recoverOnLaunch(in: reopenedContainer), 1)
            let resumedRepository = SwiftDataCaptureSessionRepository(container: reopenedContainer)
            let recoveredResult = try await resumedRepository.find(id: created.id)
            let recovered = try XCTUnwrap(recoveredResult)
            XCTAssertEqual(recovered.state, .failedRecoverable)
            XCTAssertEqual(recovered.lastErrorCode, "session.interruptedAnalysis")
            XCTAssertEqual(recovered.revision, analyzing.revision + 1)
            XCTAssertEqual(recovered.draft, draft)
            XCTAssertEqual(try SwiftDataCaptureSessionRepository.recoverOnLaunch(in: reopenedContainer), 0)

            let retry = try await resumedRepository.transition(id: recovered.id,
                                                                 expectedRevision: recovered.revision,
                                                                 to: .analyzing, errorCode: nil,
                                                                 confirmedEventID: nil)
            XCTAssertNil(retry.lastErrorCode)
            XCTAssertEqual(retry.state, .analyzing)
        }
    }

    func testFailedSaveLeavesPreviousDraftAndRevisionAfterRelaunch() async throws {
        try await withPersistentStore { container, support, legacyURL in
            let repository = SwiftDataCaptureSessionRepository(container: container)
            let created = try await repository.create(kind: .snapshot, vehicleID: nil,
                                                       draft: CaptureDraft())
            var replacement = CaptureDraft()
            replacement.odometerKilometers = 123_456
            repository.beforeSave = { throw CaptureSessionError.conflict }
            do {
                _ = try await repository.updateDraft(id: created.id,
                                                     expectedRevision: created.revision,
                                                     draft: replacement)
                XCTFail("The injected pre-commit failure must abort the write")
            } catch CaptureSessionError.conflict {
                // Expected: the dedicated ModelContext is dropped without autosaving.
            }
            let reopenedContainer = try CartrackModelContainer.make(applicationSupportURL: support,
                                                                     legacyStoreURL: legacyURL)
            let reopened = SwiftDataCaptureSessionRepository(container: reopenedContainer)
            let persistedResult = try await reopened.find(id: created.id)
            let persisted = try XCTUnwrap(persistedResult)
            XCTAssertEqual(persisted.draft, CaptureDraft())
            XCTAssertEqual(persisted.revision, created.revision)
        }
    }

    func testDiscardIsExplicitAndCorruptDraftDoesNotHideOtherSessions() async throws {
        let container = try CartrackModelContainer.make(isStoredInMemoryOnly: true)
        let repository = SwiftDataCaptureSessionRepository(container: container)
        var sensitiveDraft = CaptureDraft()
        sensitiveDraft.odometerKilometers = 123_456
        sensitiveDraft.notes = "private note"
        let first = try await repository.create(kind: .snapshot, vehicleID: nil, draft: sensitiveDraft)
        let second = try await repository.create(kind: .snapshot, vehicleID: nil, draft: CaptureDraft())
        let context = ModelContext(container)
        context.insert(OCRFieldEvidence(sessionID: first.id, fieldRawValue: "odometer",
                                        rawText: "123456", normalizedValue: "123456",
                                        confidenceDecimal: "0.9", confidenceBandRawValue: "high",
                                        algorithmVersion: "test"))
        let corrupted = try XCTUnwrap(context.fetch(FetchDescriptor<CaptureSessionRecord>())
            .first { $0.id == second.id })
        corrupted.draftData = Data("corrupt".utf8)
        try context.save()

        let index = try await repository.resumable()
        XCTAssertEqual(index.sessions.map(\.id), [first.id])
        XCTAssertEqual(index.corruptSessionIDs, [second.id])
        do {
            _ = try await repository.find(id: second.id)
            XCTFail("A corrupt draft must be reported, not silently decoded")
        } catch CaptureSessionError.corruptDraft {
            XCTAssertEqual(CaptureSessionError.corruptDraft.code, "session.corruptDraft")
        }
        try await repository.discard(id: second.id, expectedRevision: second.revision)
        try await repository.discard(id: first.id, expectedRevision: first.revision)
        let discardedResult = try await repository.find(id: first.id)
        let discarded = try XCTUnwrap(discardedResult)
        XCTAssertEqual(discarded.state, .discarded)
        XCTAssertEqual(discarded.draft, CaptureDraft())
        let evidenceAfterDiscard = try ModelContext(container).fetch(FetchDescriptor<OCRFieldEvidence>())
        XCTAssertTrue(evidenceAfterDiscard.filter { $0.sessionID == first.id }.isEmpty)
        let afterDiscard = try await repository.resumable()
        XCTAssertTrue(afterDiscard.sessions.isEmpty)
        XCTAssertTrue(afterDiscard.corruptSessionIDs.isEmpty)
    }

    func testUnknownPersistedStateIsReportedAsCorrupt() async throws {
        let container = try CartrackModelContainer.make(isStoredInMemoryOnly: true)
        let repository = SwiftDataCaptureSessionRepository(container: container)
        let created = try await repository.create(kind: .snapshot, vehicleID: nil, draft: CaptureDraft())
        let context = ModelContext(container)
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<CaptureSessionRecord>()).first)
        record.stateRawValue = "future-state"
        try context.save()
        let index = try await repository.resumable()
        XCTAssertTrue(index.sessions.isEmpty)
        XCTAssertEqual(index.corruptSessionIDs, [created.id])
    }

    func testInvalidTransitionsAndStaleRevisionDoNotChangePersistedSession() async throws {
        let container = try CartrackModelContainer.make(isStoredInMemoryOnly: true)
        let repository = SwiftDataCaptureSessionRepository(container: container)
        let created = try await repository.create(kind: .fillUp, vehicleID: nil, draft: CaptureDraft())
        do {
            _ = try await repository.transition(id: created.id, expectedRevision: created.revision,
                                                to: .confirmed, errorCode: nil,
                                                confirmedEventID: UUID())
            XCTFail("A draft cannot confirm directly")
        } catch CaptureSessionError.invalidTransition {}
        let analyzing = try await repository.transition(id: created.id,
                                                         expectedRevision: created.revision,
                                                         to: .analyzing, errorCode: nil,
                                                         confirmedEventID: nil)
        do {
            _ = try await repository.updateDraft(id: created.id, expectedRevision: created.revision,
                                                 draft: CaptureDraft())
            XCTFail("A stale revision must conflict")
        } catch CaptureSessionError.conflict {}
        let review = try await repository.transition(id: analyzing.id,
                                                      expectedRevision: analyzing.revision,
                                                      to: .review, errorCode: nil,
                                                      confirmedEventID: nil)
        do {
            _ = try await repository.transition(id: review.id, expectedRevision: review.revision,
                                                to: .confirmed, errorCode: nil,
                                                confirmedEventID: nil)
            XCTFail("Confirmation requires the saved event ID")
        } catch CaptureSessionError.missingConfirmedEventID {}
        let persistedResult = try await repository.find(id: review.id)
        let persisted = try XCTUnwrap(persistedResult)
        XCTAssertEqual(persisted.state, .review)
        XCTAssertEqual(persisted.revision, review.revision)
    }

    private func withPersistentStore(
        _ body: (ModelContainer, URL, URL) async throws -> Void
    ) async throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("CartrackCaptureSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let legacyURL = support.appendingPathComponent("unused-v1.store")
        let container = try CartrackModelContainer.make(applicationSupportURL: support,
                                                         legacyStoreURL: legacyURL)
        try await body(container, support, legacyURL)
    }
}
