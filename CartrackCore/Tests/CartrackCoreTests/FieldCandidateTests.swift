import Foundation
import XCTest
@testable import CartrackCore

final class FieldCandidateTests: XCTestCase {
    private let scorer = FieldCandidateScorer()

    func testHighMediumLowAndMissingCriticalBands() {
        let high = scorer.assess([candidate(.odometerKilometers, 175_000, recognition: 0.95, quality: 0.95)])
        let medium = scorer.assess([candidate(.tripKilometers, 945, recognition: 0.70, quality: 0.80)])
        let low = scorer.assess([candidate(.fuelLevelRemaining, 2, recognition: 0.35, quality: 0.80)])
        let missing = scorer.assess([], expectedFields: [.totalCost])

        XCTAssertEqual(high.result(for: .odometerKilometers)?.band, .high)
        XCTAssertNotNil(high.result(for: .odometerKilometers)?.selectedCandidateID)
        XCTAssertEqual(medium.result(for: .tripKilometers)?.band, .medium)
        XCTAssertNotNil(medium.result(for: .tripKilometers)?.selectedCandidateID)
        XCTAssertEqual(low.result(for: .fuelLevelRemaining)?.band, .low)
        XCTAssertNil(low.result(for: .fuelLevelRemaining)?.selectedCandidateID)
        XCTAssertEqual(missing.result(for: .totalCost)?.band, .critical)
        XCTAssertEqual(missing.result(for: .totalCost)?.validationCodes, ["field.noCandidate"])
        XCTAssertEqual(high.algorithmVersion, "field-confidence-v1")
    }

    func testTwoIndependentImagesCanPromoteMediumToHighButSamePhotoCannot() {
        let firstPhoto = UUID()
        let secondPhoto = UUID()
        let first = candidate(.odometerKilometers, 175_000, photoID: firstPhoto,
                              recognition: 0.82, quality: 0.80)
        let samePhoto = candidate(.odometerKilometers, 175_000.5, photoID: firstPhoto,
                                  recognition: 0.80, quality: 0.80)
        let otherPhoto = candidate(.odometerKilometers, 175_000.6, photoID: secondPhoto,
                                   recognition: 0.80, quality: 0.80)

        XCTAssertEqual(scorer.assess([first, samePhoto]).result(for: .odometerKilometers)?.band, .medium)
        let promoted = scorer.assess([first, otherPhoto]).result(for: .odometerKilometers)
        XCTAssertEqual(promoted?.band, .high)
        XCTAssertEqual(promoted?.candidates.count, 2)
        XCTAssertEqual(promoted?.selectedCandidateID, first.id)
    }

    func testReliableMultiImageDisagreementIsCriticalAndDoesNotSilentlyChoose() {
        let first = candidate(.odometerKilometers, 175_000, recognition: 0.95, quality: 0.95)
        let second = candidate(.odometerKilometers, 178_000, recognition: 0.93, quality: 0.93)
        let result = scorer.assess([first, second]).result(for: .odometerKilometers)

        XCTAssertEqual(result?.band, .critical)
        XCTAssertNil(result?.selectedCandidateID)
        XCTAssertEqual(result?.validationCodes, ["field.conflict"])
        XCTAssertEqual(Set(result?.candidates.map(\.candidate.id) ?? []), [first.id, second.id])
    }

    func testWeakAlternativeIsKeptButDoesNotBlockStrongReading() {
        let strong = candidate(.tripKilometers, 90, recognition: 0.96, quality: 0.95)
        let weak = candidate(.tripKilometers, 700, recognition: 0.20, quality: 0.20)
        let result = scorer.assess([weak, strong]).result(for: .tripKilometers)

        XCTAssertEqual(result?.band, .high)
        XCTAssertEqual(result?.selectedCandidateID, strong.id)
        XCTAssertEqual(result?.validationCodes, ["field.weakAlternative"])
        XCTAssertEqual(result?.candidates.count, 2)
    }

    func testAnalogGaugeDoesNotAutoselectWithoutCalibration() {
        let gauge = candidate(.fuelLevelRemaining, 2, method: .analogGauge,
                              recognition: 0.99, quality: 0.99)
        let result = scorer.assess([gauge]).result(for: .fuelLevelRemaining)
        XCTAssertEqual(result?.band, .low)
        XCTAssertNil(result?.selectedCandidateID)
        XCTAssertEqual(result?.confidence, 0.60)
    }

    func testInvalidCandidatesRemainAuditableAndCannotBeSelected() {
        let context = CandidateValidationContext(previousOdometerKilometers: 175_000,
                                                 tankCapacityGallons: 14)
        let invalid: [(FieldCandidate, String)] = [
            (candidate(.odometerKilometers, 174_000), "field.odometerRegression"),
            (candidate(.tripKilometers, -1), "field.outOfRange"),
            (candidate(.fuelLevelRemaining, 9), "field.outOfRange"),
            (candidate(.fuelLevelRemaining, 2.1), "field.offGaugeStep"),
            (candidate(.volumeGallons, 20), "field.outOfRange"),
            (candidate(.unitPrice, 0), "field.outOfRange"),
            (candidate(.totalCost, 1_000_001), "field.outOfRange"),
            (candidate(.stationName, .text("  ")), "field.emptyText"),
            (candidate(.occurredAt, .date(context.now.addingTimeInterval(172_800))), "field.futureDate"),
            (candidate(.totalCost, .text("Q473")), "field.valueTypeMismatch"),
            (candidate(.totalCost, 473, recognition: 1.2), "field.confidenceOutOfRange"),
        ]

        for (item, code) in invalid {
            let result = scorer.assess([item], context: context).result(for: item.field)
            XCTAssertEqual(result?.band, .critical, "\(item.field.rawValue): \(code)")
            XCTAssertNil(result?.selectedCandidateID)
            XCTAssertTrue(result?.validationCodes.contains(code) == true)
            XCTAssertEqual(result?.candidates.count, 1)
        }
    }

    func testFinancialEquationAcceptsRoundingAndBlocksMaterialMismatch() {
        let matching = [candidate(.volumeGallons, 11), candidate(.unitPrice, 43),
                        candidate(.totalCost, 473.04)]
        let accepted = scorer.assess(matching)
        XCTAssertEqual(accepted.result(for: .totalCost)?.band, .high)

        let mismatch = scorer.assess([candidate(.volumeGallons, 11), candidate(.unitPrice, 43),
                                      candidate(.totalCost, 450)])
        for field in [CaptureField.volumeGallons, .unitPrice, .totalCost] {
            XCTAssertEqual(mismatch.result(for: field)?.band, .critical)
            XCTAssertNil(mismatch.result(for: field)?.selectedCandidateID)
            XCTAssertTrue(mismatch.result(for: field)?.validationCodes.contains("field.financialMismatch") == true)
        }
    }

    func testTripContinuityUsesLastFillOdometerWhenAvailable() {
        let context = CandidateValidationContext(lastFillOdometerKilometers: 175_000)
        let matching = scorer.assess([candidate(.odometerKilometers, 175_945),
                                      candidate(.tripKilometers, 945)], context: context)
        XCTAssertEqual(matching.result(for: .tripKilometers)?.band, .high)

        let mismatch = scorer.assess([candidate(.odometerKilometers, 175_945),
                                      candidate(.tripKilometers, 400)], context: context)
        XCTAssertEqual(mismatch.result(for: .tripKilometers)?.band, .critical)
        XCTAssertEqual(mismatch.result(for: .tripKilometers)?.validationCodes, ["field.tripMismatch"])
        XCTAssertEqual(mismatch.result(for: .odometerKilometers)?.band, .high)
    }

    func testTextDateAndNumericTolerancePreserveIndependentCandidateSources() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let name = scorer.assess([
            candidate(.stationName, .text("Texaco"), photoID: UUID()),
            candidate(.stationName, .text(" texaco "), photoID: UUID()),
        ])
        XCTAssertEqual(name.result(for: .stationName)?.band, .high)
        let date = scorer.assess([
            candidate(.occurredAt, .date(now), photoID: UUID()),
            candidate(.occurredAt, .date(now.addingTimeInterval(55)), photoID: UUID()),
        ])
        XCTAssertEqual(date.result(for: .occurredAt)?.band, .high)
        let trip = scorer.assess([
            candidate(.tripKilometers, 945.1),
            candidate(.tripKilometers, 945.5),
        ])
        XCTAssertEqual(trip.result(for: .tripKilometers)?.band, .critical)
    }

    func testCandidateCodableRoundTripRetainsSourceAndNoImagePayload() throws {
        let item = candidate(.totalCost, 473)
        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(FieldCandidate.self, from: encoded)
        XCTAssertEqual(decoded, item)
        XCTAssertEqual(decoded.photoID, item.photoID)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("imageData"))
    }

    private func candidate(_ field: CaptureField, _ number: Decimal,
                           photoID: UUID = UUID(), method: CandidateMethod = .visionText,
                           recognition: Decimal = 0.95, quality: Decimal = 0.95) -> FieldCandidate {
        candidate(field, .number(number), photoID: photoID, method: method,
                  recognition: recognition, quality: quality)
    }

    private func candidate(_ field: CaptureField, _ value: CaptureFieldValue,
                           photoID: UUID = UUID(), method: CandidateMethod = .visionText,
                           recognition: Decimal = 0.95, quality: Decimal = 0.95) -> FieldCandidate {
        FieldCandidate(id: UUID(), field: field, value: value, rawText: "fixture",
                       unit: nil, photoID: photoID, method: method,
                       recognitionConfidence: recognition, imageQuality: quality)
    }
}
