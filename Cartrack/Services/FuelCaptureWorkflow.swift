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

        var stored = try await photos.all(sessionID: session.id)
        var imageByKind: [CaptureImageKind: UIImage] = [:]
        var photoByKind: [CaptureImageKind: LocalPhotoRecord] = [:]
        var imageIssues: [CaptureImageKind: [CaptureImageIssue]] = [:]
        var qualityByKind: [CaptureImageKind: Decimal] = [:]

        for kind in [CaptureImageKind.invoice, .odometer, .fuelLevel] {
            if let image = input.images[kind] {
                let record = try photoStore.save(image, sessionID: session.id, kind: kind)
                if let existing = stored.last(where: {
                    $0.kind == kind.rawValue && $0.sha256 == record.sha256
                }) {
                    try? photoStore.remove(record)
                    photoByKind[kind] = existing
                } else {
                    do {
                        try await photos.save(record)
                    } catch {
                        try? photoStore.remove(record)
                        throw error
                    }
                    stored.append(record)
                    photoByKind[kind] = record
                }
                imageByKind[kind] = image
            } else if let record = stored.last(where: { $0.kind == kind.rawValue }) {
                photoByKind[kind] = record
                imageByKind[kind] = try photoStore.load(record)
            }
            if let image = imageByKind[kind] {
                let preparation = try imagePipeline.prepare(image, declaredKind: kind)
                imageIssues[kind] = preparation.quality.issues
                qualityByKind[kind] = qualityScore(for: preparation.quality.issues)
            }
        }

        let photoIDs = stored.map(\.id)
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
                invoiceImage: imageByKind[.invoice],
                odometerImage: imageByKind[.odometer],
                fuelLevelImage: imageByKind[.fuelLevel],
                fuelScaleMax: NSDecimalNumber(decimal: input.fuelScaleMax).doubleValue,
                previousClusterReading: input.previousClusterReading
            )
            let candidates = makeCandidates(recognized, photos: photoByKind,
                                            qualities: qualityByKind, issues: imageIssues)
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
            try await persistEvidence(assessment, sessionID: session.id)
            session = try await sessions.transition(id: session.id, expectedRevision: session.revision,
                                                    to: .review, errorCode: nil,
                                                    confirmedEventID: nil)
            return FuelCaptureOutcome(session: session, fields: assessment.fields,
                                      imageIssues: imageIssues, recognizedText: recognized)
        } catch {
            _ = try? await sessions.transition(id: session.id, expectedRevision: session.revision,
                                               to: .failedRecoverable,
                                               errorCode: "capture.analysisFailed",
                                               confirmedEventID: nil)
            throw error
        }
    }

    private func qualityScore(for issues: [CaptureImageIssue]) -> Decimal {
        var score: Decimal = 0.95
        for issue in issues {
            switch issue {
            case .tooBlurred, .overexposed, .underexposed: score -= 0.25
            case .lowResolution, .wrongKind: score -= 0.20
            case .possibleGlare, .possibleCrop: score -= 0.10
            case .orientationCorrected: break
            }
        }
        return max(0, score)
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
        draft.odometerKilometers = draft.odometerKilometers ?? value(.odometerKilometers)
        draft.tripKilometers = draft.tripKilometers ?? value(.tripKilometers)
        draft.volumeGallons = draft.volumeGallons ?? value(.volumeGallons)
        draft.unitPrice = draft.unitPrice ?? value(.unitPrice)
        draft.totalCost = draft.totalCost ?? value(.totalCost)
        draft.fuelLevelRemaining = draft.fuelLevelRemaining ?? value(.fuelLevelRemaining)
    }

    private func persistEvidence(_ assessment: CandidateAssessment, sessionID: UUID) async throws {
        for field in assessment.fields {
            for scored in field.candidates {
                let candidate = scored.candidate
                let value: String = switch candidate.value {
                case .number(let number): String(describing: number)
                case .text(let string): string
                case .date(let date): ISO8601DateFormatter().string(from: date)
                }
                let record = OCRFieldRecord(id: candidate.id, sessionID: sessionID,
                                            ownerEventID: nil, field: candidate.field.rawValue,
                                            rawText: candidate.rawText, normalizedValue: value,
                                            unit: candidate.unit, confidence: field.confidence,
                                            confidenceBand: field.band.rawValue,
                                            sourcePhotoID: candidate.photoID,
                                            validationCodes: field.validationCodes + scored.validationCodes,
                                            wasManuallyCorrected: false,
                                            algorithmVersion: field.algorithmVersion)
                try await evidence.save(record)
            }
        }
    }
}
