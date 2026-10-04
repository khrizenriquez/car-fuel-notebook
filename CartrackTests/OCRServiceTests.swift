import UIKit
import XCTest
@testable import Cartrack

final class OCRServiceTests: XCTestCase {
    func testAnalyzeFillUpUsesInjectedRecognizerAndParser() async {
        let invoiceImage = makeImage(color: .red)
        let odometerImage = makeImage(color: .green)
        let fuelLevelImage = makeImage(color: .blue)
        let service = OCRService(recognizer: StubTextRecognizer(texts: [
            ObjectIdentifier(invoiceImage): "Galones 10.2500\nPrecio Q32.10\nTotal Q329.03",
            ObjectIdentifier(odometerImage): "Odometro 123,456 mi\nTrip 0.0",
            ObjectIdentifier(fuelLevelImage): "Nivel 8 espacios",
        ]))

        let result = await service.analyzeFillUp(
            invoiceImage: invoiceImage,
            odometerImage: odometerImage,
            fuelLevelImage: fuelLevelImage,
            fuelScaleMax: FuelLevelScale.defaultMax
        )

        XCTAssertEqual(result.invoiceText, "Galones 10.2500\nPrecio Q32.10\nTotal Q329.03")
        XCTAssertEqual(result.odometerText, "Odometro 123,456 mi\nTrip 0.0")
        XCTAssertEqual(result.fuelLevelText, "Nivel 8 espacios")
        XCTAssertEqual(result.gallons ?? 0, 10.2500, accuracy: 0.0001)
        XCTAssertEqual(result.pricePerGallon ?? 0, 32.10, accuracy: 0.001)
        XCTAssertEqual(result.totalCost ?? 0, 329.03, accuracy: 0.001)
        XCTAssertEqual(result.odometerMiles ?? 0, 123_456, accuracy: 0.001)
        XCTAssertEqual(result.tripMiles ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(result.fuelLevelRemaining ?? 0, 8, accuracy: 0.001)
    }

    func testAnalyzeSnapshotUsesInjectedRecognizerAndParsesFractionalFuelLevel() async {
        let odometerImage = makeImage(color: .purple)
        let fuelLevelImage = makeImage(color: .orange)
        let service = OCRService(recognizer: StubTextRecognizer(texts: [
            ObjectIdentifier(odometerImage): "Odo 123 620 mi\nTrip 164.0",
            ObjectIdentifier(fuelLevelImage): "Nivel 6 1/2 espacios",
        ]))

        let result = await service.analyzeSnapshot(
            odometerImage: odometerImage,
            fuelLevelImage: fuelLevelImage,
            fuelScaleMax: FuelLevelScale.defaultMax
        )

        XCTAssertEqual(result.odometerText, "Odo 123 620 mi\nTrip 164.0")
        XCTAssertEqual(result.fuelLevelText, "Nivel 6 1/2 espacios")
        XCTAssertEqual(result.odometerMiles ?? 0, 123_620, accuracy: 0.001)
        XCTAssertEqual(result.tripMiles ?? 0, 164.0, accuracy: 0.001)
        XCTAssertEqual(result.fuelLevelRemaining ?? 0, 6.5, accuracy: 0.001)
    }

    func testAnalyzeSnapshotPrefersDedicatedClusterReadingWhenAvailable() async {
        let odometerImage = makeImage(color: .brown)
        let fuelLevelImage = makeImage(color: .cyan)
        let service = OCRService(
            recognizer: StubTextRecognizer(texts: [
                ObjectIdentifier(odometerImage): "108288 miles 0160",
                ObjectIdentifier(fuelLevelImage): "Nivel 5 espacios",
            ]),
            clusterReader: StubClusterReader(readings: [
                ObjectIdentifier(odometerImage): InstrumentClusterReading(
                    odometerMiles: 108_288,
                    tripMiles: 126.3
                )
            ])
        )

        let result = await service.analyzeSnapshot(
            odometerImage: odometerImage,
            fuelLevelImage: fuelLevelImage,
            fuelScaleMax: FuelLevelScale.defaultMax
        )

        XCTAssertEqual(result.odometerMiles ?? 0, 108_288, accuracy: 0.001)
        XCTAssertEqual(result.tripMiles ?? 0, 126.3, accuracy: 0.001)
        XCTAssertTrue(result.odometerText.localizedCaseInsensitiveContains("odometer 108288 miles"))
        XCTAssertTrue(result.odometerText.localizedCaseInsensitiveContains("trip 126.3"))
    }

    func testAnalyzeSnapshotUsesRepeatedVisionPairWhenDedicatedReadingContradictsIt() async {
        let odometerImage = makeImage(color: .magenta)
        let service = OCRService(
            recognizer: StubTextRecognizer(texts: [
                ObjectIdentifier(odometerImage): """
                108768 miles 606.5
                108 768 - 606.5
                108768 606.5
                MPH
                """,
            ]),
            clusterReader: StubClusterReader(readings: [
                ObjectIdentifier(odometerImage): InstrumentClusterReading(
                    odometerMiles: 111_117,
                    tripMiles: 161.5
                )
            ])
        )

        let result = await service.analyzeSnapshot(
            odometerImage: odometerImage,
            fuelLevelImage: nil,
            fuelScaleMax: FuelLevelScale.defaultMax
        )

        XCTAssertEqual(result.odometerMiles ?? 0, 108_768, accuracy: 0.001)
        XCTAssertEqual(result.tripMiles ?? 0, 606.5, accuracy: 0.001)
    }

    func testAnalyzeSnapshotReturnsManualFallbackForUnresolvedClusterConflict() async {
        let odometerImage = makeImage(color: .darkGray)
        let service = OCRService(
            recognizer: StubTextRecognizer(texts: [
                ObjectIdentifier(odometerImage): "108768 miles 606S\nMPH",
            ]),
            clusterReader: StubClusterReader(readings: [
                ObjectIdentifier(odometerImage): InstrumentClusterReading(
                    odometerMiles: 111_117,
                    tripMiles: 161.5
                )
            ])
        )

        let result = await service.analyzeSnapshot(
            odometerImage: odometerImage,
            fuelLevelImage: nil,
            fuelScaleMax: FuelLevelScale.defaultMax
        )

        XCTAssertNil(result.odometerMiles)
        XCTAssertNil(result.tripMiles)
    }

    func testOCRImageNormalizationAppliesUIImageOrientationBeforeReadingPixels() throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 3)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 3))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 1, y: 0, width: 1, height: 3))
        }
        let rotated = try XCTUnwrap(
            source.cgImage.map {
                UIImage(cgImage: $0, scale: 1, orientation: .right)
            }
        )

        let normalized = try XCTUnwrap(rotated.normalizedCGImageForOCR())

        XCTAssertEqual(normalized.width, source.cgImage?.height)
        XCTAssertEqual(normalized.height, source.cgImage?.width)
    }

    func testAnalyzeSnapshotUsesPreviousReadingToResolveSevenSegmentCandidates() async {
        let cases: [(text: String, previous: InstrumentClusterReading, expected: InstrumentClusterReading)] = [
            (
                """
                108128 miles
                S66.6
                MPH
                """,
                InstrumentClusterReading(odometerMiles: 108_394, tripMiles: 232.3),
                InstrumentClusterReading(odometerMiles: 108_728, tripMiles: 566.6)
            ),
            (
                """
                08T49 wiles
                miles
                5812
                miles
                5313
                MPH
                """,
                InstrumentClusterReading(odometerMiles: 108_728, tripMiles: 566.6),
                InstrumentClusterReading(odometerMiles: 108_749, tripMiles: 587.3)
            ),
            (
                "108768 mileg 606.5\nMPH",
                InstrumentClusterReading(odometerMiles: 108_749, tripMiles: 587.3),
                InstrumentClusterReading(odometerMiles: 108_768, tripMiles: 606.5)
            ),
            (
                "108355 miles\n193./\nMPH",
                InstrumentClusterReading(odometerMiles: 108_335, tripMiles: 173.7),
                InstrumentClusterReading(odometerMiles: 108_355, tripMiles: 193.1)
            ),
            (
                "108335 wiles\n0T3.T\nMPH",
                InstrumentClusterReading(odometerMiles: 108_288, tripMiles: 126.3),
                InstrumentClusterReading(odometerMiles: 108_335, tripMiles: 173.7)
            ),
        ]

        for (index, testCase) in cases.enumerated() {
            let image = makeImage(color: UIColor(hue: CGFloat(index) / 3, saturation: 1, brightness: 1, alpha: 1))
            let service = OCRService(
                recognizer: StubTextRecognizer(texts: [
                    ObjectIdentifier(image): testCase.text,
                ]),
                clusterReader: StubClusterReader(readings: [:])
            )

            let result = await service.analyzeSnapshot(
                odometerImage: image,
                fuelLevelImage: nil,
                fuelScaleMax: FuelLevelScale.defaultMax,
                previousClusterReading: testCase.previous
            )

            XCTAssertEqual(
                result.odometerMiles ?? 0,
                testCase.expected.odometerMiles,
                accuracy: 0.001,
                "case \(index)"
            )
            XCTAssertEqual(
                result.tripMiles ?? 0,
                testCase.expected.tripMiles,
                accuracy: 0.001,
                "case \(index)"
            )
        }
    }

    func testAnalyzeSnapshotInfersOdometerFromMonotonicTripWhenVisionOdometerIsMissing() async {
        let image = makeImage(color: .systemIndigo)
        let service = OCRService(
            recognizer: StubTextRecognizer(texts: [
                ObjectIdentifier(image): "tripRecovery 1376 * 6341\n00833\nMPH",
            ]),
            clusterReader: StubClusterReader(readings: [:])
        )

        let result = await service.analyzeSnapshot(
            odometerImage: image,
            fuelLevelImage: nil,
            fuelScaleMax: FuelLevelScale.defaultMax,
            previousClusterReading: InstrumentClusterReading(
                odometerMiles: 108_768,
                tripMiles: 606.5
            )
        )

        XCTAssertEqual(result.odometerMiles ?? 0, 108_796, accuracy: 0.001)
        XCTAssertEqual(result.tripMiles ?? 0, 634.1, accuracy: 0.001)
    }

    func testAnalyzeSnapshotDoesNotInferOdometerFromDistantTripOnlyEvidence() async {
        let image = makeImage(color: .systemPurple)
        let service = OCRService(
            recognizer: StubTextRecognizer(texts: [
                ObjectIdentifier(image): "1000\n1263\n126.3\n1263\n00833\nMPH",
            ]),
            clusterReader: StubClusterReader(readings: [:])
        )

        let result = await service.analyzeSnapshot(
            odometerImage: image,
            fuelLevelImage: nil,
            fuelScaleMax: FuelLevelScale.defaultMax,
            previousClusterReading: InstrumentClusterReading(
                odometerMiles: 107_729,
                tripMiles: 19.4
            )
        )

        XCTAssertNil(result.odometerMiles)
        XCTAssertNil(result.tripMiles)
    }

    func testAnalyzeSnapshotDoesNotInferFromAmbiguousRecoveryDigits() async {
        let image = makeImage(color: .systemOrange)
        let service = OCRService(
            recognizer: StubTextRecognizer(texts: [
                ObjectIdentifier(image): "08 T49 mles\ntripRecovery SB13\nMPH",
            ]),
            clusterReader: StubClusterReader(readings: [:])
        )

        let result = await service.analyzeSnapshot(
            odometerImage: image,
            fuelLevelImage: nil,
            fuelScaleMax: FuelLevelScale.defaultMax,
            previousClusterReading: InstrumentClusterReading(
                odometerMiles: 108_728,
                tripMiles: 566.6
            )
        )

        XCTAssertNil(result.odometerMiles)
        XCTAssertNil(result.tripMiles)
    }

    func testAnalyzeSnapshotRejectsContextualPairThatRequiresTooManyCorrections() async {
        let image = makeImage(color: .systemTeal)
        let noisyText = (["108888 miles 3000"] + (0..<20).map { "MPH noise \($0)" })
            .joined(separator: "\n")
        let service = OCRService(
            recognizer: StubTextRecognizer(texts: [
                ObjectIdentifier(image): noisyText,
            ]),
            clusterReader: StubClusterReader(readings: [:])
        )

        let result = await service.analyzeSnapshot(
            odometerImage: image,
            fuelLevelImage: nil,
            fuelScaleMax: FuelLevelScale.defaultMax,
            previousClusterReading: InstrumentClusterReading(
                odometerMiles: 108_000,
                tripMiles: 0
            )
        )

        XCTAssertNil(result.odometerMiles)
        XCTAssertNil(result.tripMiles)
    }

    private func makeImage(color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}

private struct StubTextRecognizer: OCRTextRecognizing {
    let texts: [ObjectIdentifier: String]

    func recognizeText(from image: UIImage?) async -> String {
        guard let image else { return "" }
        return texts[ObjectIdentifier(image)] ?? ""
    }

    func recognizeInstrumentClusterText(from image: UIImage?) async -> String {
        guard let image else { return "" }
        return texts[ObjectIdentifier(image)] ?? ""
    }
}

private struct StubClusterReader: InstrumentClusterReadingProviding {
    let readings: [ObjectIdentifier: InstrumentClusterReading]

    func readDisplay(from image: UIImage) -> InstrumentClusterReading? {
        readings[ObjectIdentifier(image)]
    }
}
