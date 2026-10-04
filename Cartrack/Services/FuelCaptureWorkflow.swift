import Foundation
import SwiftData
import UIKit

protocol FuelCaptureRecognizing: Sendable {
    func analyzeFillUp(invoiceImage: UIImage?, odometerImage: UIImage?, fuelLevelImage: UIImage?,
                       fuelScaleMax: Double,
                       previousClusterReading: InstrumentClusterReading?) async -> FillUpPrefill
}

extension OCRService: FuelCaptureRecognizing {}

struct FuelCaptureInput {
    let vehicleID: UUID
    let occurredAt: Date
    let odometerUnit: OdometerUnit
    let tankCapacityGallons: Decimal
    let fuelScaleMax: Decimal
    let fuelScaleStep: Decimal
    let previousOdometerKilometers: Decimal?
    let lastFillOdometerKilometers: Decimal?
    let previousClusterReading: InstrumentClusterReading?
    let images: [CaptureImageKind: UIImage]
}

struct FuelCaptureOutcome {
    let session: CaptureSession
    let fields: [FieldResult]
    let imageIssues: [CaptureImageKind: [CaptureImageIssue]]
    let recognizedText: FillUpPrefill
    let images: [CaptureImageKind: UIImage]
}

@MainActor
final class FuelCaptureWorkflow {
    private let sessions: CaptureSessionRepository
    private let photos: PhotoAssetRepository
    private let evidence: OCRFieldEvidenceRepository
    private let photoStore: CapturePhotoStore
    private let imagePipeline: CaptureImagePipeline
    private let recognizer: FuelCaptureRecognizing
    private let scorer = FieldCandidateScorer()

    init(sessions: CaptureSessionRepository, photos: PhotoAssetRepository,
         evidence: OCRFieldEvidenceRepository,
         photoStore: CapturePhotoStore = CapturePhotoStore(),
         imagePipeline: CaptureImagePipeline = CaptureImagePipeline(),
         recognizer: FuelCaptureRecognizing = OCRService()) {
        self.sessions = sessions
        self.photos = photos
        self.evidence = evidence
        self.photoStore = photoStore
        self.imagePipeline = imagePipeline
        self.recognizer = recognizer
    }

    convenience init(container: ModelContainer) {
        self.init(sessions: SwiftDataCaptureSessionRepository(container: container),
                  photos: SwiftDataPhotoAssetRepository(context: ModelContext(container)),
                  evidence: SwiftDataOCRFieldEvidenceRepository(context: ModelContext(container)))
    }

    func analyze(input: FuelCaptureInput, sessionID: UUID? = nil) async throws -> FuelCaptureOutcome {
        var session: CaptureSession
        if let sessionID {
            guard let existing = try await sessions.find(id: sessionID),
                  existing.kind == .fillUp, existing.vehicleID == input.vehicleID else {
                throw CaptureSessionError.notFound
            }
            session = existing
        } else {
            var draft = CaptureDraft()
            draft.occurredAt = input.occurredAt
            session = try await sessions.create(kind: .fillUp, vehicleID: input.vehicleID, draft: draft)
        }

        let prepared = try await CaptureWorkflowSupport.prepare(
            sessionID: session.id, selectedImages: input.images,
            supportedKinds: [.invoice, .odometer, .fuelLevel], photos: photos,
            store: photoStore, pipeline: imagePipeline
        )
        let photoIDs = prepared.assets.map(\.id)
        if session.draft.photoIDs != photoIDs || session.draft.occurredAt != input.occurredAt {
            var draft = session.draft
            draft.photoIDs = photoIDs
            draft.occurredAt = input.occurredAt
            session = try await sessions.updateDraft(id: session.id,
                                                     expectedRevision: session.revision, draft: draft)
        }
        session = try await sessions.transition(id: session.id, expectedRevision: session.revision,
                                                to: .analyzing, errorCode: nil,
                                                confirmedEventID: nil)
        do {
            let recognized = await recognizer.analyzeFillUp(
                invoiceImage: prepared.images[.invoice],
                odometerImage: prepared.images[.odometer],
                fuelLevelImage: prepared.images[.fuelLevel],
                fuelScaleMax: NSDecimalNumber(decimal: input.fuelScaleMax).doubleValue,
                previousClusterReading: input.previousClusterReading
            )
            let candidates = makeCandidates(recognized, photos: prepared.selectedAssets,
                                            qualities: prepared.quality, issues: prepared.issues)
            let context = CandidateValidationContext(
                previousOdometerKilometers: input.previousOdometerKilometers,
                lastFillOdometerKilometers: input.lastFillOdometerKilometers,
                tankCapacityGallons: input.tankCapacityGallons,
                fuelScaleMax: input.fuelScaleMax,
                fuelScaleStep: input.fuelScaleStep
            )
            let assessment = scorer.assess(candidates,
                                           expectedFields: [.odometerKilometers, .volumeGallons,
                                                            .unitPrice, .totalCost], context: context)
            var draft = session.draft
            apply(assessment, to: &draft)
            session = try await sessions.updateDraft(id: session.id,
                                                     expectedRevision: session.revision, draft: draft)
            try await CaptureWorkflowSupport.persistEvidence(assessment, sessionID: session.id,
                                                             repository: evidence)
            session = try await sessions.transition(id: session.id, expectedRevision: session.revision,
                                                    to: .review, errorCode: nil,
                                                    confirmedEventID: nil)
            return FuelCaptureOutcome(session: session, fields: assessment.fields,
                                      imageIssues: prepared.issues, recognizedText: recognized,
                                      images: prepared.images)
        } catch {
            _ = try? await sessions.transition(id: session.id, expectedRevision: session.revision,
                                               to: .failedRecoverable,
                                               errorCode: "capture.analysisFailed",
                                               confirmedEventID: nil)
            throw error
        }
    }

    private func makeCandidates(_ result: FillUpPrefill,
                                photos: [CaptureImageKind: LocalPhotoRecord],
                                qualities: [CaptureImageKind: Decimal],
                                issues: [CaptureImageKind: [CaptureImageIssue]]) -> [FieldCandidate] {
        var output: [FieldCandidate] = []
        func append(_ field: CaptureField, _ value: Double?, kind: CaptureImageKind,
                    method: CandidateMethod = .visionText) {
            guard let value, value.isFinite, let photo = photos[kind],
                  issues[kind]?.contains(.wrongKind) != true,
                  let decimal = Decimal(string: String(value)) else { return }
            output.append(FieldCandidate(id: UUID(), field: field, value: .number(decimal),
                                         rawText: String(value), unit: nil, photoID: photo.id,
                                         method: method, recognitionConfidence: 0.80,
                                         imageQuality: qualities[kind] ?? 0.50))
        }
        let odometerKilometers = result.odometerMiles.map(UnitConversion.milesToKilometers)
        let tripKilometers = result.tripMiles.map(UnitConversion.milesToKilometers)
        append(.odometerKilometers, odometerKilometers, kind: .odometer, method: .digitalDisplay)
        append(.tripKilometers, tripKilometers, kind: .odometer, method: .digitalDisplay)
        append(.volumeGallons, result.gallons, kind: .invoice)
        append(.unitPrice, result.pricePerGallon, kind: .invoice)
        append(.totalCost, result.totalCost, kind: .invoice)
        append(.fuelLevelRemaining, result.fuelLevelRemaining,
               kind: .fuelLevel, method: .analogGauge)
        return output
    }

    private func apply(_ assessment: CandidateAssessment, to draft: inout CaptureDraft) {
        func value(_ field: CaptureField) -> Decimal? {
            guard case .number(let number) = assessment.result(for: field)?.selectedValue else { return nil }
            return number
        }
        if !draft.isManuallyEdited(.odometerKilometers) { draft.odometerKilometers = value(.odometerKilometers) }
        if !draft.isManuallyEdited(.tripKilometers) { draft.tripKilometers = value(.tripKilometers) }
        if !draft.isManuallyEdited(.volumeGallons) { draft.volumeGallons = value(.volumeGallons) }
        if !draft.isManuallyEdited(.unitPrice) { draft.unitPrice = value(.unitPrice) }
        if !draft.isManuallyEdited(.totalCost) { draft.totalCost = value(.totalCost) }
        if !draft.isManuallyEdited(.fuelLevelRemaining) { draft.fuelLevelRemaining = value(.fuelLevelRemaining) }
    }

}
