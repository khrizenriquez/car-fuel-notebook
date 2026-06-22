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
}
