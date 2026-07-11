import UIKit
import XCTest
@testable import Cartrack

final class LocalExampleImageOCRTests: XCTestCase {
    func testOrderedOdometerFixturesParseExpectedMileageAndTrip() async throws {
        let service = OCRService()

        for fixture in odometerFixtures() {
            let image = try loadImage(at: fixture.url)
            let result = await service.analyzeSnapshot(
                odometerImage: image,
                fuelLevelImage: nil,
                fuelScaleMax: FuelLevelScale.defaultMax
            )

            XCTAssertFalse(result.odometerText.trimmed.isEmpty, fixture.url.lastPathComponent)
            XCTAssertEqual(result.odometerMiles ?? 0, fixture.odometerMiles, accuracy: 1, fixture.url.lastPathComponent)
            XCTAssertEqual(result.tripMiles ?? 0, fixture.tripMiles, accuracy: 0.2, fixture.url.lastPathComponent)
            XCTAssertNil(result.fuelLevelRemaining, fixture.url.lastPathComponent)
        }
    }

    func testOrderedFuelGaugeFixturesKeepFuelLevelManual() async throws {
        let service = OCRService()

        for url in fuelGaugeFixtureURLs() {
            let result = await service.analyzeSnapshot(
                odometerImage: nil,
                fuelLevelImage: try loadImage(at: url),
                fuelScaleMax: FuelLevelScale.defaultMax
            )

            XCTAssertNil(
                result.fuelLevelRemaining,
                "La aguja analogica de \(url.lastPathComponent) no debe convertirse en un valor automatico sin confirmacion manual."
            )
        }
    }

    func testTexacoInvoiceFixtureParsesRequiredFuelPurchaseValues() async throws {
        let service = OCRService()
        let invoiceURL = repoRoot().appendingPathComponent("Invoices/Examples/2026-07-09_195613_IMG_5418.jpeg")

        let result = await service.analyzeFillUp(
            invoiceImage: try loadImage(at: invoiceURL),
            odometerImage: nil,
            fuelLevelImage: nil,
            fuelScaleMax: FuelLevelScale.defaultMax
        )

        XCTAssertEqual(result.gallons ?? 0, 3.791, accuracy: 0.0001)
        XCTAssertEqual(result.pricePerGallon ?? 0, 39.57, accuracy: 0.001)
        XCTAssertEqual(result.totalCost ?? 0, 150.00, accuracy: 0.001)
        XCTAssertTrue(result.invoiceText.localizedCaseInsensitiveContains("TEXACO"))
    }

    private func odometerFixtures() -> [(url: URL, odometerMiles: Double, tripMiles: Double)] {
        let root = repoRoot()
        return [
            ("Odometer/Examples/2026-06-14_173358_IMG_4676.jpeg", 107_729, 19.4),
            ("Odometer/Examples/2026-07-08_171215_IMG_5366.jpeg", 108_288, 126.3),
            ("Odometer/Examples/2026-07-09_081311_IMG_5381.jpeg", 108_309, 147.6),
            ("Odometer/Examples/2026-07-09_180342_IMG_5413.jpeg", 108_335, 173.7),
            ("Odometer/Examples/2026-07-09_195255_IMG_5416.jpeg", 108_337, 175.4),
            ("Odometer/Examples/2026-07-09_210156_IMG_5419.jpeg", 108_355, 193.1),
            ("Odometer/Examples/2026-07-10_074640_IMG_5421.jpeg", 108_365, 203.3),
            ("Odometer/Examples/2026-07-10_135521_IMG_5427.jpeg", 108_375, 213.1),
            ("Odometer/Examples/2026-07-10_225052_image-2.jpeg", 108_394, 232.3),
        ].map { path, odometerMiles, tripMiles in
            (root.appendingPathComponent(path), odometerMiles, tripMiles)
        }
    }

    private func fuelGaugeFixtureURLs() -> [URL] {
        let root = repoRoot()
        return [
            "FuelLevel/Examples/2026-06-14_173400_IMG_4677.jpeg",
            "FuelLevel/Examples/2026-07-06_170441_IMG_5331.jpeg",
            "FuelLevel/Examples/2026-07-08_171218_IMG_5367.jpeg",
            "FuelLevel/Examples/2026-07-09_081314_IMG_5382.jpeg",
            "FuelLevel/Examples/2026-07-09_180348_IMG_5414.jpeg",
            "FuelLevel/Examples/2026-07-09_195300_IMG_5417.jpeg",
            "FuelLevel/Examples/2026-07-09_210205_IMG_5420.jpeg",
            "FuelLevel/Examples/2026-07-10_074642_IMG_5422.jpeg",
            "FuelLevel/Examples/2026-07-10_135523_IMG_5428.jpeg",
            "FuelLevel/Examples/2026-07-10_225057_image-1.jpeg",
        ].map { root.appendingPathComponent($0) }
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadImage(at url: URL) throws -> UIImage {
        guard let image = UIImage(contentsOfFile: url.path) else {
            XCTFail("No se pudo cargar la imagen en \(url.path)")
            throw LocalFixtureError.unreadableImage
        }
        return image
    }
}

private enum LocalFixtureError: Error {
    case unreadableImage
}
