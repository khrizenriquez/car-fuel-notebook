import SwiftData
import UIKit
import XCTest
@testable import Cartrack

@MainActor
final class CaptureConfirmationServiceTests: XCTestCase {
    func testSnapshotConfirmationIsAtomicAndCannotBeRepeated() async throws {
        let (container, vehicle, review) = try await fixture(kind: .snapshot)
        var finalDraft = review.draft
        finalDraft.odometerKilometers = 175_000
        finalDraft.fuelLevelRemaining = 2
        let eventID = try CaptureConfirmationService.confirm(
            container: container, sessionID: review.id,
            expectedRevision: review.revision, vehicleID: vehicle.id,
            kind: .snapshot, finalDraft: finalDraft,
            images: [.odometer: image()]
        ) { storedVehicle, context in
            let event = SnapshotEvent(vehicle: storedVehicle, odometerKilometers: 175_000,
                                      fuelLevelRemaining: 2)
            context.insert(event)
            return event.id
        }
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SnapshotEvent>()).map(\.id), [eventID])
        let assets = try context.fetch(FetchDescriptor<ImageAsset>())
        XCTAssertEqual(assets.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(assets.first).localPath))
        let sessionResult = try await SwiftDataCaptureSessionRepository(container: container)
            .find(id: review.id)
        let session = try XCTUnwrap(sessionResult)
        XCTAssertEqual(session.state, .confirmed)
        XCTAssertEqual(session.confirmedEventID, eventID)
        XCTAssertEqual(session.draft, finalDraft)
        XCTAssertThrowsError(try CaptureConfirmationService.confirm(
            container: container, sessionID: review.id,
            expectedRevision: review.revision, vehicleID: vehicle.id,
            kind: .snapshot, finalDraft: finalDraft, images: [:]
        ) { storedVehicle, context in
            let duplicate = SnapshotEvent(vehicle: storedVehicle)
            context.insert(duplicate)
            return duplicate.id
        })
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<SnapshotEvent>()).count, 1)
        for asset in assets { try? ImageStorageService.shared.deleteImage(at: asset.localPath) }
    }

    func testInjectedFailureRollsBackEventAndLeavesSessionReview() async throws {
        let (container, vehicle, review) = try await fixture(kind: .fillUp)
        do {
            _ = try CaptureConfirmationService.confirm(
                container: container, sessionID: review.id,
                expectedRevision: review.revision, vehicleID: vehicle.id,
                kind: .fillUp, finalDraft: review.draft, images: [:],
                buildEvent: { storedVehicle, context in
                    let fill = FuelFillEvent(vehicle: storedVehicle)
                    context.insert(fill)
                    return fill.id
                }, beforeSave: { throw CaptureSessionError.conflict }
            )
            XCTFail("Injected failure should abort the transaction")
        } catch CaptureSessionError.conflict {}
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<FuelFillEvent>()).isEmpty)
        let sessionResult = try await SwiftDataCaptureSessionRepository(container: container)
            .find(id: review.id)
        XCTAssertEqual(try XCTUnwrap(sessionResult).state, .review)
    }

    private func fixture(kind: CaptureSessionKind) async throws -> (ModelContainer, Vehicle, CaptureSession) {
        let container = try CartrackModelContainer.make(isStoredInMemoryOnly: true)
        let vehicle = Vehicle(name: "Z4", make: "BMW", modelName: "Z4", year: 2003)
        let context = ModelContext(container)
        context.insert(vehicle)
        try context.save()
        let repository = SwiftDataCaptureSessionRepository(container: container)
        let created = try await repository.create(kind: kind, vehicleID: vehicle.id,
                                                  draft: CaptureDraft())
        let analyzing = try await repository.transition(id: created.id,
                                                         expectedRevision: created.revision,
                                                         to: .analyzing, errorCode: nil,
                                                         confirmedEventID: nil)
        let review = try await repository.transition(id: analyzing.id,
                                                      expectedRevision: analyzing.revision,
                                                      to: .review, errorCode: nil,
                                                      confirmedEventID: nil)
        return (container, vehicle, review)
    }

private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
    }
}

final class CaptureConfidencePresentationTests: XCTestCase {
    func testHighMediumLowAndCriticalHaveDistinctUserActions() {
        XCTAssertEqual(CaptureConfidencePresentation.label(.high, manuallyResolved: false), "Alta")
        XCTAssertEqual(CaptureConfidencePresentation.tone(.high, manuallyResolved: false), .success)
        XCTAssertEqual(CaptureConfidencePresentation.label(.medium, manuallyResolved: false), "Media · revisar")
        XCTAssertEqual(CaptureConfidencePresentation.tone(.medium, manuallyResolved: false), .warning)
        XCTAssertEqual(CaptureConfidencePresentation.label(.low, manuallyResolved: false), "Baja · corregir")
        XCTAssertTrue(CaptureConfidencePresentation.requiresRetake(.low))
        XCTAssertEqual(CaptureConfidencePresentation.label(.critical, manuallyResolved: false), "Conflicto · corregir")
        XCTAssertEqual(CaptureConfidencePresentation.tone(.critical, manuallyResolved: false), .error)
        XCTAssertTrue(CaptureConfidencePresentation.requiresRetake(.critical))
        XCTAssertEqual(CaptureConfidencePresentation.label(.critical, manuallyResolved: true),
                       "Corregido manualmente")
        XCTAssertEqual(CaptureConfidencePresentation.tone(.critical, manuallyResolved: true), .success)
        XCTAssertTrue(CaptureConfidencePresentation.explanation(for: "field.financialMismatch")?
            .contains("Galones") == true)
        XCTAssertTrue(CaptureConfidencePresentation.explanation(for: .tooBlurred)
            .contains("desenfocada"))
    }
}
