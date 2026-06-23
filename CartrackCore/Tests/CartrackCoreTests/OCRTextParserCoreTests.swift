import XCTest
@testable import CartrackCore

final class OCRTextParserCoreTests: XCTestCase {
    private let parser = OCRTextParser()

    func testSanitizedOCRFixturesParseExpectedFields() throws {
        let fixtures = try loadOCRFixtures()
        XCTAssertFalse(fixtures.isEmpty)

        for fixture in fixtures {
            switch fixture.kind {
            case .fillUp:
                let result = parser.parseFillUp(
                    invoiceText: fixture.invoiceText,
                    odometerText: fixture.odometerText,
                    fuelLevelText: fixture.fuelLevelText,
                    fuelScaleMax: fixture.fuelScaleMax
                )
                assertEqual(result.gallons, fixture.expected.gallons, fixture: fixture, field: "gallons", accuracy: 0.0001)
                assertEqual(result.pricePerGallon, fixture.expected.pricePerGallon, fixture: fixture, field: "pricePerGallon")
                assertEqual(result.totalCost, fixture.expected.totalCost, fixture: fixture, field: "totalCost")
                assertEqual(result.odometerMiles, fixture.expected.odometerMiles, fixture: fixture, field: "odometerMiles")
                assertEqual(result.tripMiles, fixture.expected.tripMiles, fixture: fixture, field: "tripMiles")
                assertEqual(result.fuelLevelRemaining, fixture.expected.fuelLevelRemaining, fixture: fixture, field: "fuelLevelRemaining")
            case .snapshot:
                let result = parser.parseSnapshot(
                    odometerText: fixture.odometerText,
                    fuelLevelText: fixture.fuelLevelText,
                    fuelScaleMax: fixture.fuelScaleMax
                )
                assertEqual(result.odometerMiles, fixture.expected.odometerMiles, fixture: fixture, field: "odometerMiles")
                assertEqual(result.tripMiles, fixture.expected.tripMiles, fixture: fixture, field: "tripMiles")
                assertEqual(result.fuelLevelRemaining, fixture.expected.fuelLevelRemaining, fixture: fixture, field: "fuelLevelRemaining")
            }
        }
    }

    func testExtractNumbersSupportsDotAndCommaDecimals() {
        XCTAssertEqual(parser.extractNumbers(from: "Q329.03 10,2500 gal 32.10"), [329.03, 10.2500, 32.10])
        XCTAssertEqual(parser.extractNumbers(from: "ODO 123,456 mi"), [123456])
    }

    func testExtractNumbersSupportsMixedLocaleSeparators() {
        XCTAssertEqual(parser.extractNumbers(from: "Q1,234.56 Q1.234,56"), [1234.56, 1234.56])
        XCTAssertEqual(parser.extractNumbers(from: "1,234,567 1.234.567"), [1234567, 1234567])
    }

    func testExtractNumbersSupportsSpaceSeparatedThousandsFromOdometerOCR() {
        XCTAssertEqual(parser.extractNumbers(from: "ODO 123 456 mi"), [123456])
        XCTAssertEqualOptional(parser.parseLargestMileage(from: "BMW Z4\nODO 123 456 mi\nTRIP 0.0"), 123456, accuracy: 0.001)
    }

    func testParseFillUpReadsInvoiceOdometerAndFuelLevel() {
        let invoice = """
        Galones 10.2500
        Precio por galon 32.10
        Total pagado Q329.03
        """
        let odometer = "ODO 123456 TRIP 0.0"
        let fuel = "Nivel restante 8.0 espacios"

        let result = parser.parseFillUp(invoiceText: invoice, odometerText: odometer, fuelLevelText: fuel, fuelScaleMax: 8)

        XCTAssertEqualOptional(result.gallons, 10.2500, accuracy: 0.0001)
        XCTAssertEqualOptional(result.pricePerGallon, 32.10, accuracy: 0.0001)
        XCTAssertEqualOptional(result.totalCost, 329.03, accuracy: 0.0001)
        XCTAssertEqualOptional(result.odometerMiles, 123456, accuracy: 0.001)
        XCTAssertEqualOptional(result.tripMiles, 0, accuracy: 0.001)
        XCTAssertEqualOptional(result.fuelLevelRemaining, 8, accuracy: 0.001)
    }

    func testParseSnapshotRoundsFuelLevelToQuarterStep() {
        let result = parser.parseSnapshot(
            odometerText: "millas 123620 trip 164.0",
            fuelLevelText: "quedan 6.37 espacios",
            fuelScaleMax: 8
        )

        XCTAssertEqualOptional(result.odometerMiles, 123620, accuracy: 0.001)
        XCTAssertEqualOptional(result.tripMiles, 164.0, accuracy: 0.001)
        XCTAssertEqualOptional(result.fuelLevelRemaining, 6.25, accuracy: 0.001)
    }

    func testParserReadsEnhancedBmwSevenSegmentOdometerOCR() {
        let odometerOCR = """
        DTET4 miles 0730
        I23456 mils 073.0
        MPH
        """

        let result = parser.parseSnapshot(
            odometerText: odometerOCR,
            fuelLevelText: "",
            fuelScaleMax: 8
        )

        XCTAssertEqualOptional(result.odometerMiles, 123456, accuracy: 0.001)
        XCTAssertEqualOptional(result.tripMiles, 73.0, accuracy: 0.001)
    }

    func testFuelLevelParserDoesNotUseAnalogGaugeNoiseWithoutContext() {
        let analogGaugeOCR = """
        RAKE
        2
        4
        1/2
        1/1
        1/minx1000
        """

        XCTAssertNil(parser.parseFuelLevel(from: analogGaugeOCR, fuelScaleMax: 8))
    }

    func testParsingFallsBackToReasonableCandidates() {
        XCTAssertEqualOptional(parser.parseGallons(from: "11.34 32.10 329.03"), 11.34, accuracy: 0.001)
        XCTAssertEqualOptional(parser.parsePricePerGallon(from: "abc 32.10 xyz"), 32.10, accuracy: 0.001)
        XCTAssertEqualOptional(parser.parseTotalCost(from: "abc 329.03 xyz"), 329.03, accuracy: 0.001)
    }

    func testParseFillUpReadsGuatemalaStyleInvoiceFixture() {
        let invoice = """
        ESTACION SERVICIO
        Fecha 20/06/2026
        Producto SUPER
        Cantidad 10.2500 GAL
        Precio Unitario Q32.10
        Importe Q329.03
        Total a pagar Q329.03
        """
        let odometer = """
        BMW Z4 2.5i
        ODO 123,456 mi
        TRIP 0.0
        """
        let fuel = """
        BMW Z4
        Nivel tanque
        Quedan 8 de 8 espacios
        """

        let result = parser.parseFillUp(invoiceText: invoice, odometerText: odometer, fuelLevelText: fuel, fuelScaleMax: 8)

        XCTAssertEqualOptional(result.gallons, 10.2500, accuracy: 0.0001)
        XCTAssertEqualOptional(result.pricePerGallon, 32.10, accuracy: 0.001)
        XCTAssertEqualOptional(result.totalCost, 329.03, accuracy: 0.001)
        XCTAssertEqualOptional(result.odometerMiles, 123456, accuracy: 0.001)
        XCTAssertEqualOptional(result.tripMiles, 0, accuracy: 0.001)
        XCTAssertEqualOptional(result.fuelLevelRemaining, 8, accuracy: 0.001)
    }

    func testParseFillUpReadsAbbreviatedPumpReceiptFixture() {
        let invoice = """
        FACTURA CAMBIO DE ACEITE? NO
        COMBUSTIBLE SUPER
        Despachado: 10.2500 GAL
        P.GAL Q 32.10
        TOTAL Q 329.03
        """
        let odometer = "ODO 123 456 MI\nTRIP 0.0"
        let fuel = "Tanque lleno: 8 espacios restantes"

        let result = parser.parseFillUp(invoiceText: invoice, odometerText: odometer, fuelLevelText: fuel, fuelScaleMax: 8)

        XCTAssertEqualOptional(result.gallons, 10.2500, accuracy: 0.0001)
        XCTAssertEqualOptional(result.pricePerGallon, 32.10, accuracy: 0.001)
        XCTAssertEqualOptional(result.totalCost, 329.03, accuracy: 0.001)
        XCTAssertEqualOptional(result.odometerMiles, 123456, accuracy: 0.001)
        XCTAssertEqualOptional(result.tripMiles, 0, accuracy: 0.001)
        XCTAssertEqualOptional(result.fuelLevelRemaining, 8, accuracy: 0.001)
    }

    func testParserUsesContextForNoisyFuelLevelInsteadOfVehicleModelNumber() {
        let result = parser.parseSnapshot(
            odometerText: "BMW Z4 2.5i\nODO 123620\nTRIP 164.0",
            fuelLevelText: "BMW Z4\nQuedan 6.5 de 8 espacios",
            fuelScaleMax: 8
        )

        XCTAssertEqualOptional(result.odometerMiles, 123620, accuracy: 0.001)
        XCTAssertEqualOptional(result.tripMiles, 164.0, accuracy: 0.001)
        XCTAssertEqualOptional(result.fuelLevelRemaining, 6.5, accuracy: 0.001)
    }

    func testParserReadsCommaDecimalCurrencyInvoiceFixture() {
        let invoice = """
        GALONES: 10,2500
        P/GAL Q 32,10
        TOTAL A PAGAR: Q 329,03
        """

        XCTAssertEqualOptional(parser.parseGallons(from: invoice), 10.2500, accuracy: 0.0001)
        XCTAssertEqualOptional(parser.parsePricePerGallon(from: invoice), 32.10, accuracy: 0.001)
        XCTAssertEqualOptional(parser.parseTotalCost(from: invoice), 329.03, accuracy: 0.001)
    }

    func testParserReadsValueBeforeUnitLabels() {
        XCTAssertEqualOptional(parser.parseGallons(from: "10.2500 GAL"), 10.2500, accuracy: 0.0001)
        XCTAssertEqualOptional(parser.parseFuelLevel(from: "6.5 espacios restantes", fuelScaleMax: 8), 6.5, accuracy: 0.001)
    }

    func testParserReadsFractionalFuelLevelOCR() {
        XCTAssertEqualOptional(parser.parseFuelLevel(from: "BMW Z4\nQuedan 6 1/2 de 8 espacios", fuelScaleMax: 8), 6.5, accuracy: 0.001)
    }

    func testParserReadsCommonAbbreviatedPriceLabels() {
        XCTAssertEqualOptional(parser.parsePricePerGallon(from: "P.U. Q32.10"), 32.10, accuracy: 0.001)
        XCTAssertEqualOptional(parser.parsePricePerGallon(from: "P/U Q32.10"), 32.10, accuracy: 0.001)
    }

    func testMileageParsingIgnoresTinyValuesForOdometer() {
        XCTAssertEqualOptional(parser.parseLargestMileage(from: "trip 150.2 odo 123456"), 123456, accuracy: 0.001)
        XCTAssertNil(parser.parseLargestMileage(from: "trip 150.2"))
    }

    func testFuelLevelParsingRejectsOutOfRangeValues() {
        XCTAssertNil(parser.parseFuelLevel(from: "quedan 9 espacios", fuelScaleMax: 8))
    }

    private func loadOCRFixtures() throws -> [OCRFixture] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "ocr-fixtures", withExtension: "json")
                ?? Bundle.module.url(
                    forResource: "ocr-fixtures",
                    withExtension: "json",
                    subdirectory: "Fixtures/OCR"
                )
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([OCRFixture].self, from: data)
    }

    private func assertEqual(
        _ actual: Double?,
        _ expected: Double?,
        fixture: OCRFixture,
        field: String,
        accuracy: Double = 0.001
    ) {
        guard let expected else { return }
        XCTAssertNotNil(actual, "\(fixture.name) should parse \(field)")
        XCTAssertEqual(actual ?? .nan, expected, accuracy: accuracy, "\(fixture.name) should parse \(field)")
    }
}

private struct OCRFixture: Decodable {
    let name: String
    let kind: OCRFixtureKind
    let fuelScaleMax: Double
    let invoiceText: String
    let odometerText: String
    let fuelLevelText: String
    let expected: ExpectedOCRFields
}

private enum OCRFixtureKind: String, Decodable {
    case fillUp
    case snapshot
}

private struct ExpectedOCRFields: Decodable {
    let gallons: Double?
    let pricePerGallon: Double?
    let totalCost: Double?
    let odometerMiles: Double?
    let tripMiles: Double?
    let fuelLevelRemaining: Double?
}
