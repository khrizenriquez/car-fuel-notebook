import Foundation

enum CaptureField: String, Codable, CaseIterable, Sendable {
    case odometerKilometers
    case tripKilometers
    case fuelLevelRemaining
    case volumeGallons
    case unitPrice
    case totalCost
    case stationName
    case occurredAt
}

enum CaptureFieldValue: Codable, Equatable, Sendable {
    case number(Decimal)
    case text(String)
    case date(Date)
}

enum CandidateMethod: String, Codable, Sendable {
    case visionText
    case digitalDisplay
    case analogGauge
}

struct FieldCandidate: Codable, Equatable, Sendable {
    let id: UUID
    let field: CaptureField
    let value: CaptureFieldValue
    let rawText: String
    let unit: String?
    let photoID: UUID
    let method: CandidateMethod
    let recognitionConfidence: Decimal
    let imageQuality: Decimal
}

struct ScoredFieldCandidate: Equatable, Sendable {
    let candidate: FieldCandidate
    let score: Decimal
    let validationCodes: [String]
}

enum FieldConfidenceBand: String, Codable, Sendable {
    case high
    case medium
    case low
    case critical
}

struct FieldResult: Equatable, Sendable {
    let field: CaptureField
    let candidates: [ScoredFieldCandidate]
    var selectedCandidateID: UUID?
    var confidence: Decimal
    var band: FieldConfidenceBand
    var validationCodes: [String]
    let algorithmVersion: String

    var selectedValue: CaptureFieldValue? {
        candidates.first { $0.candidate.id == selectedCandidateID }?.candidate.value
    }
}

struct CandidateValidationContext: Sendable {
    var previousOdometerKilometers: Decimal? = nil
    var lastFillOdometerKilometers: Decimal? = nil
    var tankCapacityGallons: Decimal? = nil
    var fuelScaleMax: Decimal = 8
    var fuelScaleStep: Decimal = 0.25
    var now: Date = .now
}

struct CandidateAssessment: Equatable, Sendable {
    let fields: [FieldResult]
    let algorithmVersion: String

    func result(for field: CaptureField) -> FieldResult? {
        fields.first { $0.field == field }
    }
}

struct FieldCandidateScorer {
    static let algorithmVersion = "field-confidence-v1"
    private let highThreshold: Decimal = Decimal(string: "0.85")!
    private let mediumThreshold: Decimal = Decimal(string: "0.65")!

    func assess(_ candidates: [FieldCandidate], expectedFields: Set<CaptureField> = [],
                context: CandidateValidationContext = CandidateValidationContext()) -> CandidateAssessment {
        let fields = Set(candidates.map(\.field)).union(expectedFields)
        var results = fields.map { field in
            evaluate(field, candidates: candidates.filter { $0.field == field }, context: context)
        }
        results.sort { $0.field.rawValue < $1.field.rawValue }
        validateFinancialEquation(&results)
        validateTripContinuity(&results, context: context)
        return CandidateAssessment(fields: results, algorithmVersion: Self.algorithmVersion)
    }

    private func evaluate(_ field: CaptureField, candidates: [FieldCandidate],
                          context: CandidateValidationContext) -> FieldResult {
        guard !candidates.isEmpty else {
            return FieldResult(field: field, candidates: [], selectedCandidateID: nil,
                               confidence: 0, band: .critical,
                               validationCodes: ["field.noCandidate"],
                               algorithmVersion: Self.algorithmVersion)
        }
        let scored = candidates.map { candidate in
            let codes = validate(candidate, context: context)
            let boundedRecognition = clamp(candidate.recognitionConfidence)
            let boundedQuality = clamp(candidate.imageQuality)
            var score = boundedRecognition * Decimal(string: "0.75")!
                + boundedQuality * Decimal(string: "0.25")!
            if candidate.method == .analogGauge { score = min(score, Decimal(string: "0.60")!) }
            if !codes.isEmpty { score = min(score, Decimal(string: "0.49")!) }
            return ScoredFieldCandidate(candidate: candidate, score: score, validationCodes: codes)
        }.sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.candidate.id.uuidString < rhs.candidate.id.uuidString }
            return lhs.score > rhs.score
        }
        guard let best = scored.first(where: { $0.validationCodes.isEmpty }) else {
            return FieldResult(field: field, candidates: scored, selectedCandidateID: nil,
                               confidence: scored.first?.score ?? 0, band: .critical,
                               validationCodes: Array(Set(scored.flatMap(\.validationCodes))).sorted(),
                               algorithmVersion: Self.algorithmVersion)
        }
        let agreement = scored.filter { item in
            item.validationCodes.isEmpty && sameValue(item.candidate.value, best.candidate.value, field: field)
        }
        let reliableDisagreement = scored.contains { item in
            item.validationCodes.isEmpty && item.score >= mediumThreshold
                && !sameValue(item.candidate.value, best.candidate.value, field: field)
        }
        if reliableDisagreement {
            return FieldResult(field: field, candidates: scored, selectedCandidateID: nil,
                               confidence: best.score, band: .critical,
                               validationCodes: ["field.conflict"],
                               algorithmVersion: Self.algorithmVersion)
        }
        let independentPhotos = Set(agreement.map { $0.candidate.photoID }).count
        let confidence = min(1, best.score + (independentPhotos > 1 ? Decimal(string: "0.05")! : 0))
        let band: FieldConfidenceBand = confidence >= highThreshold ? .high
            : confidence >= mediumThreshold ? .medium : .low
        let selectedID = band == .low ? nil : best.candidate.id
        let codes = scored.contains { item in
            item.validationCodes.isEmpty && !sameValue(item.candidate.value, best.candidate.value, field: field)
        } ? ["field.weakAlternative"] : []
        return FieldResult(field: field, candidates: scored, selectedCandidateID: selectedID,
                           confidence: confidence, band: band, validationCodes: codes,
                           algorithmVersion: Self.algorithmVersion)
    }

    private func validate(_ candidate: FieldCandidate, context: CandidateValidationContext) -> [String] {
        guard (0...1).contains(candidate.recognitionConfidence),
              (0...1).contains(candidate.imageQuality) else { return ["field.confidenceOutOfRange"] }
        switch (candidate.field, candidate.value) {
        case (.odometerKilometers, .number(let value)):
            if value < 0 || value >= 10_000_000 { return ["field.outOfRange"] }
            if let previous = context.previousOdometerKilometers, value < previous {
                return ["field.odometerRegression"]
            }
        case (.tripKilometers, .number(let value)):
            if value < 0 || value >= 10_000 { return ["field.outOfRange"] }
        case (.fuelLevelRemaining, .number(let value)):
            if value < 0 || value > context.fuelScaleMax { return ["field.outOfRange"] }
            if context.fuelScaleStep > 0 {
                var quotient = value / context.fuelScaleStep
                var rounded = Decimal()
                NSDecimalRound(&rounded, &quotient, 0, .plain)
                if absolute(quotient - rounded) > Decimal(string: "0.02")! {
                    return ["field.offGaugeStep"]
                }
            }
        case (.volumeGallons, .number(let value)):
            if value <= 0 || value > (context.tankCapacityGallons ?? 100) * Decimal(string: "1.10")! {
                return ["field.outOfRange"]
            }
        case (.unitPrice, .number(let value)), (.totalCost, .number(let value)):
            if value <= 0 || value > 1_000_000 { return ["field.outOfRange"] }
        case (.stationName, .text(let value)):
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ["field.emptyText"] }
        case (.occurredAt, .date(let value)):
            if value > context.now.addingTimeInterval(86_400) { return ["field.futureDate"] }
        default:
            return ["field.valueTypeMismatch"]
        }
        return []
    }

    private func validateFinancialEquation(_ results: inout [FieldResult]) {
        guard let gallons = number(.volumeGallons, in: results),
              let price = number(.unitPrice, in: results),
              let total = number(.totalCost, in: results) else { return }
        let difference = absolute(total - gallons * price)
        guard difference > Decimal(string: "0.05")! else { return }
        for field in [CaptureField.volumeGallons, .unitPrice, .totalCost] {
            invalidate(field, code: "field.financialMismatch", in: &results)
        }
    }

    private func validateTripContinuity(_ results: inout [FieldResult], context: CandidateValidationContext) {
        guard let lastFill = context.lastFillOdometerKilometers,
              let odometer = number(.odometerKilometers, in: results),
              let trip = number(.tripKilometers, in: results),
              odometer >= lastFill else { return }
        let expected = odometer - lastFill
        let tolerance = max(2, expected * Decimal(string: "0.03")!)
        if absolute(expected - trip) > tolerance {
            invalidate(.tripKilometers, code: "field.tripMismatch", in: &results)
        }
    }

    private func number(_ field: CaptureField, in results: [FieldResult]) -> Decimal? {
        guard let result = results.first(where: { $0.field == field }),
              case .number(let value) = result.selectedValue else { return nil }
        return value
    }

    private func invalidate(_ field: CaptureField, code: String, in results: inout [FieldResult]) {
        guard let index = results.firstIndex(where: { $0.field == field }) else { return }
        results[index].selectedCandidateID = nil
        results[index].band = .critical
        results[index].validationCodes.append(code)
    }

    private func sameValue(_ lhs: CaptureFieldValue, _ rhs: CaptureFieldValue, field: CaptureField) -> Bool {
        switch (lhs, rhs) {
        case (.number(let left), .number(let right)):
            let tolerance: Decimal = switch field {
            case .odometerKilometers: 1.61
            case .tripKilometers: Decimal(string: "0.32")!
            case .fuelLevelRemaining: Decimal(string: "0.25")!
            case .volumeGallons, .unitPrice, .totalCost: Decimal(string: "0.01")!
            default: 0
            }
            return absolute(left - right) <= tolerance
        case (.text(let left), .text(let right)):
            return left.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(right.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
        case (.date(let left), .date(let right)):
            return abs(left.timeIntervalSince(right)) <= 60
        default:
            return false
        }
    }

    private func clamp(_ value: Decimal) -> Decimal { min(1, max(0, value)) }
    private func absolute(_ value: Decimal) -> Decimal { value < 0 ? -value : value }
}
