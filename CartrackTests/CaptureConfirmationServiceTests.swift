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
        let newID = UUID()
        let integrityInput = EventIntegrityInput(
            reading: EventIntegrityReading(id: newID, occurredAt: .now,
                                           odometerKilometers: 175_000, tripKilometers: nil),
            fuelLevelRemaining: 2, fuelScaleMax: 8, fuelScaleStep: 0.25,
            financial: nil, overrideReason: ""
        )
        let eventID = try CaptureConfirmationService.confirm(
            container: container, sessionID: review.id,
            expectedRevision: review.revision, vehicleID: vehicle.id,
            kind: .snapshot, finalDraft: finalDraft,
            images: [.odometer: image()], integrityInput: integrityInput
        ) { storedVehicle, context in
            let event = SnapshotEvent(id: newID, vehicle: storedVehicle, odometerKilometers: 175_000,
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
            kind: .snapshot, finalDraft: finalDraft, images: [:],
            integrityInput: integrityInput
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
        let newID = UUID()
        let integrityInput = EventIntegrityInput(
            reading: EventIntegrityReading(id: newID, occurredAt: .now,
                                           odometerKilometers: 175_000, tripKilometers: nil),
            fuelLevelRemaining: 8, fuelScaleMax: 8, fuelScaleStep: 0.25,
            financial: .init(gallons: 10, unitPrice: 42, totalCost: 420),
            overrideReason: ""
        )
        do {
            _ = try CaptureConfirmationService.confirm(
                container: container, sessionID: review.id,
                expectedRevision: review.revision, vehicleID: vehicle.id,
                kind: .fillUp, finalDraft: review.draft, images: [:],
                integrityInput: integrityInput,
                buildEvent: { storedVehicle, context in
                    let fill = FuelFillEvent(id: newID, vehicle: storedVehicle)
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

    func testIntegrityRejectionLeavesEventSessionAndEvidenceUnchanged() async throws {
        let (container, vehicle, review) = try await fixture(kind: .snapshot)
        let priorContext = ModelContext(container)
        priorContext.insert(SnapshotEvent(date: Date(timeIntervalSince1970: 1_700_000_000),
                                          vehicle: try XCTUnwrap(priorContext.fetch(FetchDescriptor<Vehicle>()).first),
                                          odometerKilometers: 2_000))
        try priorContext.save()
        let eventID = UUID()
        let input = EventIntegrityInput(
            reading: EventIntegrityReading(id: eventID,
                                           occurredAt: Date(timeIntervalSince1970: 1_700_086_400),
                                           odometerKilometers: 1_900, tripKilometers: 5),
            fuelLevelRemaining: 2, fuelScaleMax: 8, fuelScaleStep: 0.25,
            financial: nil, overrideReason: ""
        )
        XCTAssertThrowsError(try CaptureConfirmationService.confirm(
            container: container, sessionID: review.id, expectedRevision: review.revision,
            vehicleID: vehicle.id, kind: .snapshot, finalDraft: review.draft,
            images: [:], integrityInput: input
        ) { storedVehicle, context in
            let event = SnapshotEvent(id: eventID, vehicle: storedVehicle)
            context.insert(event)
            return event.id
        }) {
            XCTAssertEqual($0 as? EventIntegrityError, .odometerRegression)
        }
        let after = ModelContext(container)
        XCTAssertEqual(try after.fetch(FetchDescriptor<SnapshotEvent>()).count, 1)
        XCTAssertTrue(try after.fetch(FetchDescriptor<OCRFieldEvidence>()).isEmpty)
        let session = try await SwiftDataCaptureSessionRepository(container: container).find(id: review.id)
        XCTAssertEqual(session?.state, .review)
    }

    func testAuditedOdometerOverrideCommitsWithEvent() async throws {
        let (container, vehicle, review) = try await fixture(kind: .snapshot)
        let priorContext = ModelContext(container)
        priorContext.insert(SnapshotEvent(date: Date(timeIntervalSince1970: 1_700_000_000),
                                          vehicle: try XCTUnwrap(priorContext.fetch(FetchDescriptor<Vehicle>()).first),
                                          odometerKilometers: 2_000))
        try priorContext.save()
        let eventID = UUID()
        let input = EventIntegrityInput(
            reading: EventIntegrityReading(id: eventID,
                                           occurredAt: Date(timeIntervalSince1970: 1_700_086_400),
                                           odometerKilometers: 1_900, tripKilometers: 5),
            fuelLevelRemaining: 2, fuelScaleMax: 8, fuelScaleStep: 0.25,
            financial: nil, overrideReason: "Odómetro reparado"
        )
        _ = try CaptureConfirmationService.confirm(
            container: container, sessionID: review.id, expectedRevision: review.revision,
            vehicleID: vehicle.id, kind: .snapshot, finalDraft: review.draft,
            images: [:], integrityInput: input
        ) { storedVehicle, context in
            let event = SnapshotEvent(id: eventID, vehicle: storedVehicle,
                                      odometerKilometers: 1_900)
            context.insert(event)
            return event.id
        }
        let evidence = try ModelContext(container).fetch(FetchDescriptor<OCRFieldEvidence>())
        XCTAssertEqual(evidence.count, 1)
        XCTAssertEqual(evidence[0].ownerEventID, eventID)
        XCTAssertEqual(evidence[0].rawText, "Odómetro reparado")
        XCTAssertEqual(evidence[0].algorithmVersion, "integrity-override-v1")
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
