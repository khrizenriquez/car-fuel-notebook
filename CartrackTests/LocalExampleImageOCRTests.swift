import SwiftData
import UIKit
import XCTest
@testable import Cartrack

final class LocalExampleImageOCRTests: XCTestCase {
    @MainActor
    func testPrivateFillUpWorkflowPrefillsFromRealPhotos() async throws {
        let manifest = try loadManifest()
        let scenario = try XCTUnwrap(manifest.scenarios.first { $0.kind == .fillUp && !$0.excluded })
        let expected = try XCTUnwrap(scenario.expected)
        let container = try CartrackModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        let vehicle = Vehicle(name: "Private fixture Z4", make: "BMW", modelName: "Z4", year: 2003)
        context.insert(vehicle)
        try context.save()
        let photoRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CartrackPrivateWorkflow-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: photoRoot) }
        var images: [CaptureImageKind: UIImage] = [:]
        images[.invoice] = try loadOptionalImage(relativePath: scenario.invoiceImage, scenarioID: scenario.id)
        images[.odometer] = try loadOptionalImage(relativePath: scenario.odometerImage, scenarioID: scenario.id)
        images[.fuelLevel] = try loadOptionalImage(relativePath: scenario.fuelImage, scenarioID: scenario.id)
        let workflow = FuelCaptureWorkflow(
            sessions: SwiftDataCaptureSessionRepository(container: container),
            photos: SwiftDataPhotoAssetRepository(context: ModelContext(container)),
            evidence: SwiftDataOCRFieldEvidenceRepository(context: ModelContext(container)),
            photoStore: CapturePhotoStore(rootURL: photoRoot)
        )
        let input = FuelCaptureInput(vehicleID: vehicle.id, occurredAt: .now,
                                     odometerUnit: .miles, tankCapacityGallons: 14,
                                     fuelScaleMax: 8, fuelScaleStep: 0.25,
                                     previousOdometerKilometers: nil,
                                     lastFillOdometerKilometers: nil,
                                     previousClusterReading: nil, images: images)
        let outcome = try await workflow.analyze(input: input)
        XCTAssertEqual(outcome.session.state, .review)
        XCTAssertEqual(outcome.session.draft.photoIDs.count, 3)
        let financeDiagnostics = "recognized=(\(String(describing: outcome.recognizedText.gallons)),\(String(describing: outcome.recognizedText.pricePerGallon)),\(String(describing: outcome.recognizedText.totalCost))); fields=\(outcome.fields.filter { [.volumeGallons, .unitPrice, .totalCost].contains($0.field) }.map { "\($0.field.rawValue):\($0.band.rawValue):\($0.validationCodes)" }); issues=\(outcome.imageIssues)"
        if let gallons = expected.gallons {
            let actual = try XCTUnwrap(outcome.session.draft.volumeGallons, financeDiagnostics)
            XCTAssertEqual(NSDecimalNumber(decimal: actual).doubleValue, gallons,
                           accuracy: scenario.tolerance.gallons)
        }
        if let price = expected.pricePerGallon {
            let actual = try XCTUnwrap(outcome.session.draft.unitPrice)
            XCTAssertEqual(NSDecimalNumber(decimal: actual).doubleValue, price,
                           accuracy: scenario.tolerance.pricePerGallon)
        }
        if let total = expected.totalCost {
            let actual = try XCTUnwrap(outcome.session.draft.totalCost)
            XCTAssertEqual(NSDecimalNumber(decimal: actual).doubleValue, total,
                           accuracy: scenario.tolerance.totalCost)
        }
        if let odometerMiles = expected.odometerMiles {
            let actual = try XCTUnwrap(outcome.session.draft.odometerKilometers)
            XCTAssertEqual(UnitConversion.kilometersToMiles(NSDecimalNumber(decimal: actual).doubleValue),
                           odometerMiles, accuracy: scenario.tolerance.odometerMiles)
        }
        let resumed = try await workflow.analyze(
            input: FuelCaptureInput(vehicleID: vehicle.id, occurredAt: .now,
                                    odometerUnit: .miles, tankCapacityGallons: 14,
                                    fuelScaleMax: 8, fuelScaleStep: 0.25,
                                    previousOdometerKilometers: nil,
                                    lastFillOdometerKilometers: nil,
                                    previousClusterReading: nil, images: [:]),
            sessionID: outcome.session.id
        )
        XCTAssertEqual(resumed.session.state, .review)
        XCTAssertEqual(resumed.session.draft.photoIDs, outcome.session.draft.photoIDs)
        if let gallons = expected.gallons {
            XCTAssertEqual(try XCTUnwrap(resumed.recognizedText.gallons), gallons,
                           accuracy: scenario.tolerance.gallons)
        }
    }

    func testPrivateImagePreparationKeepsDeclaredEvidenceAndVariantsLocal() throws {
        let manifest = try loadManifest()
        let pipeline = CaptureImagePipeline()
        let scenarioFilter = ProcessInfo.processInfo.environment["CARTRACK_PRIVATE_SCENARIO_ID"]

        for scenario in manifest.scenarios
        where !scenario.excluded && (scenarioFilter == nil || scenario.id == scenarioFilter) {
            let images: [(String?, CaptureImageKind)] = [
                (scenario.invoiceImage, .invoice),
                (scenario.odometerImage, .odometer),
                (scenario.fuelImage, .fuelLevel),
            ]
            for (path, kind) in images {
                guard let image = try loadOptionalImage(relativePath: path, scenarioID: scenario.id) else {
                    continue
                }
                let result = try pipeline.prepare(image, declaredKind: kind)
                XCTAssertFalse(result.quality.issues.contains(.wrongKind),
                               "scenario=\(scenario.id), declared=\(kind.rawValue), inferred=\(result.classification.kind.rawValue)")
                XCTAssertFalse(result.variants.isEmpty, "scenario=\(scenario.id)")
                XCTAssertTrue(result.variants.allSatisfy {
                    max($0.image.width, $0.image.height) <= 2_200
                }, "scenario=\(scenario.id)")
            }
        }
    }

    func testPrivateManifestCoversEveryAvailableImage() throws {
        let manifest = try loadManifest()
        let declaredPaths = Set(manifest.scenarios.flatMap(\.imagePaths))
        let availablePaths = try availablePrivateImagePaths()

        XCTAssertEqual(
            declaredPaths,
            availablePaths,
            """
            El manifiesto privado debe clasificar todas las evidencias locales.
            Sin declarar: \(availablePaths.subtracting(declaredPaths).sorted())
            Sin archivo: \(declaredPaths.subtracting(availablePaths).sorted())
            """
        )
    }

    func testAllPrivateImageScenariosMatchExpectedOCR() async throws {
        let manifest = try loadManifest()
        let service = OCRService()
        let scenarioFilter = ProcessInfo.processInfo.environment["CARTRACK_PRIVATE_SCENARIO_ID"]

        for scenario in manifest.scenarios
        where !scenario.excluded && (scenarioFilter == nil || scenario.id == scenarioFilter) {
            let usablePreviousReading = previousReading(before: scenario, in: manifest)

            switch scenario.kind {
            case .snapshot:
                let result = await service.analyzeSnapshot(
                    odometerImage: try loadOptionalImage(
                        relativePath: scenario.odometerImage,
                        scenarioID: scenario.id
                    ),
                    fuelLevelImage: try loadOptionalImage(
                        relativePath: scenario.fuelImage,
                        scenarioID: scenario.id
                    ),
                    fuelScaleMax: FuelLevelScale.defaultMax,
                    previousClusterReading: usablePreviousReading
                )
                assertSnapshot(result, matches: scenario)

            case .fillUp:
                let result = await service.analyzeFillUp(
                    invoiceImage: try loadOptionalImage(
                        relativePath: scenario.invoiceImage,
                        scenarioID: scenario.id
                    ),
                    odometerImage: try loadOptionalImage(
                        relativePath: scenario.odometerImage,
                        scenarioID: scenario.id
                    ),
                    fuelLevelImage: try loadOptionalImage(
                        relativePath: scenario.fuelImage,
                        scenarioID: scenario.id
                    ),
                    fuelScaleMax: FuelLevelScale.defaultMax,
                    previousClusterReading: usablePreviousReading
                )
                assertFillUp(result, matches: scenario)
            }

        }
    }

    func testPriorityDigitalScenariosDoNotDependOnExactFileSignature() async throws {
        let manifest = try loadManifest()
        let service = OCRService()
        let priorityIDs = [
            "z4-2026-07-23-1941",
            "z4-2026-07-24-1351",
            "z4-2026-07-24-2255",
        ]
        let scenarioFilter = ProcessInfo.processInfo.environment["CARTRACK_PRIVATE_SCENARIO_ID"]

        for scenarioID in priorityIDs where scenarioFilter == nil || scenarioID == scenarioFilter {
            guard let scenario = manifest.scenarios.first(where: { $0.id == scenarioID }) else {
                XCTFail("Falta el escenario prioritario \(scenarioID)")
                continue
            }
            guard let original = try loadOptionalImage(
                relativePath: scenario.odometerImage,
                scenarioID: scenario.id
            ) else {
                XCTFail("Falta imagen de odometro para \(scenario.id)")
                continue
            }
            guard let variant = normalizedJPEGVariant(of: original) else {
                XCTFail("No se pudo crear variante para \(scenario.id)")
                continue
            }
            let previousReading = previousReading(
                before: scenario,
                in: manifest
            )

            let originalResult = await service.analyzeSnapshot(
                odometerImage: original,
                fuelLevelImage: nil,
                fuelScaleMax: FuelLevelScale.defaultMax,
                previousClusterReading: previousReading
            )
            assertSnapshot(originalResult, matches: scenario)

            let result = await service.analyzeSnapshot(
                odometerImage: variant,
                fuelLevelImage: nil,
                fuelScaleMax: FuelLevelScale.defaultMax,
                previousClusterReading: previousReading
            )
            let isExact = optionalValuesMatch(
                result.odometerMiles,
                scenario.expected?.odometerMiles,
                accuracy: scenario.tolerance.odometerMiles
            ) && optionalValuesMatch(
                result.tripMiles,
                scenario.expected?.tripMiles,
                accuracy: scenario.tolerance.tripMiles
            )
            let isSafeManualFallback = result.odometerMiles == nil && result.tripMiles == nil

            XCTAssertTrue(
                isExact || isSafeManualFallback,
                """
                Una variante nunca debe producir valores incorrectos:
                \(snapshotDiagnostic(result, scenarioID: scenario.id))
                """
            )
        }
    }

    private func assertSnapshot(
        _ result: SnapshotPrefill,
        matches scenario: PrivateImageScenario,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let expected = scenario.expected else { return }
        let diagnostic = snapshotDiagnostic(result, scenarioID: scenario.id)

        assertOptional(
            result.odometerMiles,
            equals: expected.odometerMiles,
            accuracy: scenario.tolerance.odometerMiles,
            message: diagnostic,
            file: file,
            line: line
        )
        assertOptional(
            result.tripMiles,
            equals: expected.tripMiles,
            accuracy: scenario.tolerance.tripMiles,
            message: diagnostic,
            file: file,
            line: line
        )

        if expected.expectsFuelLevelOCR {
            if let expectedFuelLevel = expected.fuelLevelOCR {
                assertOptional(
                    result.fuelLevelRemaining,
                    equals: expectedFuelLevel,
                    accuracy: scenario.tolerance.fuelLevelOCR,
                    message: diagnostic,
                    file: file,
                    line: line
                )
            } else {
                XCTAssertNil(
                    result.fuelLevelRemaining,
                    "scenario=\(scenario.id) expected=MANUAL_REQUIRED\n\(diagnostic)",
                    file: file,
                    line: line
                )
            }
        }
    }

    private func assertFillUp(
        _ result: FillUpPrefill,
        matches scenario: PrivateImageScenario,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let expected = scenario.expected else { return }
        let diagnostic = fillUpDiagnostic(result, scenarioID: scenario.id)

        assertOptional(
            result.odometerMiles,
            equals: expected.odometerMiles,
            accuracy: scenario.tolerance.odometerMiles,
            message: diagnostic,
            file: file,
            line: line
        )
        assertOptional(
            result.tripMiles,
            equals: expected.tripMiles,
            accuracy: scenario.tolerance.tripMiles,
            message: diagnostic,
            file: file,
            line: line
        )
        assertOptional(
            result.gallons,
            equals: expected.gallons,
            accuracy: scenario.tolerance.gallons,
            message: diagnostic,
            file: file,
            line: line
        )
        assertOptional(
            result.pricePerGallon,
            equals: expected.pricePerGallon,
            accuracy: scenario.tolerance.pricePerGallon,
            message: diagnostic,
            file: file,
            line: line
        )
        assertOptional(
            result.totalCost,
            equals: expected.totalCost,
            accuracy: scenario.tolerance.totalCost,
            message: diagnostic,
            file: file,
            line: line
        )

        if expected.expectsFuelLevelOCR {
            if let expectedFuelLevel = expected.fuelLevelOCR {
                assertOptional(
                    result.fuelLevelRemaining,
                    equals: expectedFuelLevel,
                    accuracy: scenario.tolerance.fuelLevelOCR,
                    message: diagnostic,
                    file: file,
                    line: line
                )
            } else {
                XCTAssertNil(
                    result.fuelLevelRemaining,
                    "scenario=\(scenario.id) expected=MANUAL_REQUIRED\n\(diagnostic)",
                    file: file,
                    line: line
                )
            }
        }

        if let expectedText = expected.invoiceTextContains {
            XCTAssertTrue(
                result.invoiceText.localizedCaseInsensitiveContains(expectedText),
                "scenario=\(scenario.id) expected invoice text containing \(expectedText)\n\(diagnostic)",
                file: file,
                line: line
            )
        }
    }

    private func assertOptional(
        _ actual: Double?,
        equals expected: Double?,
        accuracy: Double,
        message: String,
        file: StaticString,
        line: UInt
    ) {
        guard let expected else { return }
        guard let actual else {
            XCTFail(
                "expected=\(expected) observed=nil tolerance=\(accuracy)\n\(message)",
                file: file,
                line: line
            )
            return
        }
        XCTAssertEqual(
            actual,
            expected,
            accuracy: accuracy,
            "expected=\(expected) observed=\(actual) tolerance=\(accuracy)\n\(message)",
            file: file,
            line: line
        )
    }

    private func optionalValuesMatch(
        _ actual: Double?,
        _ expected: Double?,
        accuracy: Double
    ) -> Bool {
        switch (actual, expected) {
        case (.none, .none):
            return true
        case let (.some(actual), .some(expected)):
            return abs(actual - expected) <= accuracy
        default:
            return false
        }
    }

    private func previousReading(
        before scenario: PrivateImageScenario,
        in manifest: PrivateImageScenarioManifest
    ) -> InstrumentClusterReading? {
        guard let index = manifest.scenarios.firstIndex(where: { $0.id == scenario.id }) else {
            return nil
        }

        for previousScenario in manifest.scenarios[..<index].reversed() {
            guard let odometer = previousScenario.expected?.odometerMiles,
                  let trip = previousScenario.expected?.tripMiles,
                  let currentOdometer = scenario.expected?.odometerMiles,
                  let currentTrip = scenario.expected?.tripMiles,
                  odometer <= currentOdometer,
                  trip <= currentTrip
            else {
                continue
            }
            return InstrumentClusterReading(
                odometerMiles: odometer,
                tripMiles: trip
            )
        }
        return nil
    }

    private func loadManifest() throws -> PrivateImageScenarioManifest {
        guard requiresPrivateFixtures else {
            throw XCTSkip("La matriz de imágenes privadas se ejecuta con Scripts/verify_private_image_scenarios.sh.")
        }
        let url = manifestURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            if requiresPrivateFixtures {
                XCTFail("Falta el manifiesto privado requerido: \(url.path)")
                throw LocalFixtureError.missingManifest
            }
            throw XCTSkip(
                "Paquete privado ausente. Usa CARTRACK_REQUIRE_PRIVATE_FIXTURES=1 para exigirlo."
            )
        }
        return try PrivateImageScenarioManifest.load(from: url)
    }

    private func loadOptionalImage(
        relativePath: String?,
        scenarioID: String
    ) throws -> UIImage? {
        guard let relativePath else { return nil }
        let url = repoRoot().appendingPathComponent(relativePath)
        guard let image = UIImage(contentsOfFile: url.path) else {
            XCTFail("scenario=\(scenarioID) no se pudo cargar \(url.path)")
            throw LocalFixtureError.unreadableImage
        }
        return image
    }

    private func normalizedJPEGVariant(of image: UIImage) -> UIImage? {
        let maxDimension: CGFloat = 1_600
        let largestDimension = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / largestDimension)
        let size = CGSize(
            width: max(1, (image.size.width * scale).rounded()),
            height: max(1, (image.size.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let normalized = renderer.image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = normalized.jpegData(compressionQuality: 0.78) else {
            return nil
        }
        return UIImage(data: data)
    }

    private func availablePrivateImagePaths() throws -> Set<String> {
        let supportedExtensions = Set(["heic", "heif", "jpg", "jpeg", "png", "tif", "tiff"])
        var paths = Set<String>()

        for folder in ["Invoices/Examples", "Odometer/Examples", "FuelLevel/Examples"] {
            let folderURL = repoRoot().appendingPathComponent(folder)
            guard let enumerator = FileManager.default.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator
            where supportedExtensions.contains(url.pathExtension.lowercased()) {
                paths.insert(relativePath(for: url))
            }
        }

        return paths
    }

    private func relativePath(for url: URL) -> String {
        let rootPath = repoRoot().standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func snapshotDiagnostic(
        _ result: SnapshotPrefill,
        scenarioID: String
    ) -> String {
        """
        scenario=\(scenarioID)
        odometer=\(result.odometerMiles?.description ?? "nil")
        trip=\(result.tripMiles?.description ?? "nil")
        fuel=\(result.fuelLevelRemaining?.description ?? "nil")
        odometerText:
        \(result.odometerText)
        fuelText:
        \(result.fuelLevelText)
        """
    }

    private func fillUpDiagnostic(
        _ result: FillUpPrefill,
        scenarioID: String
    ) -> String {
        """
        scenario=\(scenarioID)
        gallons=\(result.gallons?.description ?? "nil")
        pricePerGallon=\(result.pricePerGallon?.description ?? "nil")
        totalCost=\(result.totalCost?.description ?? "nil")
        odometer=\(result.odometerMiles?.description ?? "nil")
        trip=\(result.tripMiles?.description ?? "nil")
        fuel=\(result.fuelLevelRemaining?.description ?? "nil")
        invoiceText:
        \(result.invoiceText)
        odometerText:
        \(result.odometerText)
        fuelText:
        \(result.fuelLevelText)
        """
    }

    private var requiresPrivateFixtures: Bool {
        let value = ProcessInfo.processInfo.environment["CARTRACK_REQUIRE_PRIVATE_FIXTURES"]?
            .lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    private func manifestURL() -> URL {
        repoRoot().appendingPathComponent(
            "CartrackTests/Fixtures/private-image-scenarios.json"
        )
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private enum LocalFixtureError: Error {
    case missingManifest
    case unreadableImage
}
