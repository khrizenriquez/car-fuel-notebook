import Foundation
import UIKit

struct PreparedCaptureImages {
    let assets: [LocalPhotoRecord]
    let images: [CaptureImageKind: UIImage]
    let selectedAssets: [CaptureImageKind: LocalPhotoRecord]
    let issues: [CaptureImageKind: [CaptureImageIssue]]
    let quality: [CaptureImageKind: Decimal]
}

@MainActor
enum CaptureWorkflowSupport {
    static func prepare(sessionID: UUID, selectedImages: [CaptureImageKind: UIImage],
                        supportedKinds: [CaptureImageKind], photos: PhotoAssetRepository,
                        store: CapturePhotoStore,
                        pipeline: CaptureImagePipeline) async throws -> PreparedCaptureImages {
        var assets = try await photos.all(sessionID: sessionID)
        var images: [CaptureImageKind: UIImage] = [:]
        var selectedAssets: [CaptureImageKind: LocalPhotoRecord] = [:]
        var issues: [CaptureImageKind: [CaptureImageIssue]] = [:]
        var quality: [CaptureImageKind: Decimal] = [:]

        for kind in supportedKinds {
            if let image = selectedImages[kind] {
                let newRecord = try store.save(image, sessionID: sessionID, kind: kind)
                if let existing = assets.last(where: {
                    $0.kind == kind.rawValue && $0.sha256 == newRecord.sha256
                }) {
                    try? store.remove(newRecord)
                    selectedAssets[kind] = existing
                } else {
                    do {
                        try await photos.save(newRecord)
                    } catch {
                        try? store.remove(newRecord)
                        throw error
                    }
                    assets.append(newRecord)
                    selectedAssets[kind] = newRecord
                }
                images[kind] = image
            } else if let existing = assets.last(where: { $0.kind == kind.rawValue }) {
                selectedAssets[kind] = existing
                images[kind] = try store.load(existing)
            }
            if let image = images[kind] {
                let preparation = try pipeline.prepare(image, declaredKind: kind)
                issues[kind] = preparation.quality.issues
                quality[kind] = qualityScore(for: preparation.quality.issues)
            }
        }
        return PreparedCaptureImages(assets: assets, images: images,
                                     selectedAssets: selectedAssets, issues: issues,
                                     quality: quality)
    }

    static func persistEvidence(_ assessment: CandidateAssessment, sessionID: UUID,
                                repository: OCRFieldEvidenceRepository) async throws {
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
                try await repository.save(record)
            }
        }
    }

    private static func qualityScore(for issues: [CaptureImageIssue]) -> Decimal {
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
}
