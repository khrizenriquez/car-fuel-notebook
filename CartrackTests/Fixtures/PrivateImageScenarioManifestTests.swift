import XCTest
@testable import Cartrack

final class PrivateImageScenarioManifestTests: XCTestCase {
    func testDecodesSnapshotFillUpAndExcludedScenarios() throws {
        let manifest = try PrivateImageScenarioManifest.decode(
            data: Data(
                """
                {
                  "version": 1,
                  "scenarios": [
                    {
                      "id": "snapshot-one",
                      "kind": "snapshot",
                      "odometerImage": "odometer.jpg",
                      "fuelImage": "fuel.jpg",
                      "expected": {
                        "odometerMiles": 108768,
                        "tripMiles": 606.5,
                        "fuelLevelOCR": null
                      },
                      "tolerance": {
                        "odometerMiles": 1,
                        "tripMiles": 0.2
                      },
                      "ui": {
                        "manualFuelSpaces": 2,
                        "runInSimulator": true
                      }
                    },
                    {
                      "id": "fill-one",
                      "kind": "fillUp",
                      "invoiceImage": "invoice.jpg",
                      "expected": {
                        "gallons": 3.791,
                        "pricePerGallon": 39.57,
                        "totalCost": 150
                      }
                    },
                    {
                      "id": "excluded-one",
                      "kind": "snapshot",
                      "excluded": true,
                      "exclusionReason": "Image is intentionally unavailable."
                    }
                  ]
                }
                """.utf8
            )
        )

        XCTAssertEqual(manifest.version, 1)
        XCTAssertEqual(manifest.scenarios.count, 3)
        XCTAssertEqual(manifest.scenarios[0].kind, .snapshot)
        XCTAssertEqual(manifest.scenarios[0].expected?.odometerMiles, 108_768)
        XCTAssertTrue(manifest.scenarios[0].expected?.expectsFuelLevelOCR == true)
        XCTAssertNil(manifest.scenarios[0].expected?.fuelLevelOCR)
        XCTAssertEqual(manifest.scenarios[0].ui?.manualFuelSpaces, 2)
        XCTAssertEqual(manifest.scenarios[1].kind, .fillUp)
        XCTAssertEqual(manifest.scenarios[1].expected?.gallons, 3.791)
        XCTAssertFalse(manifest.scenarios[1].expected?.expectsFuelLevelOCR == true)
        XCTAssertTrue(manifest.scenarios[2].excluded)
    }

    func testRejectsDuplicateScenarioIDs() {
        assertManifestError(
            """
            {
              "version": 1,
              "scenarios": [
                {"id": "duplicate", "kind": "snapshot", "odometerImage": "one.jpg"},
                {"id": "duplicate", "kind": "snapshot", "odometerImage": "two.jpg"}
              ]
            }
            """,
            expected: .duplicateID("duplicate")
        )
    }

    func testRejectsActiveScenarioWithoutImages() {
        assertManifestError(
            """
            {
              "version": 1,
              "scenarios": [
                {"id": "empty", "kind": "snapshot"}
              ]
            }
            """,
            expected: .missingImages("empty")
        )
    }

    func testRejectsNegativeTolerance() {
        assertManifestError(
            """
            {
              "version": 1,
              "scenarios": [
                {
                  "id": "negative",
                  "kind": "snapshot",
                  "odometerImage": "odometer.jpg",
                  "tolerance": {"odometerMiles": -1}
                }
              ]
            }
            """,
            expected: .negativeTolerance("negative")
        )
    }

    func testRequiresReasonForExcludedScenario() {
        assertManifestError(
            """
            {
              "version": 1,
              "scenarios": [
                {
                  "id": "excluded",
                  "kind": "snapshot",
                  "excluded": true
                }
              ]
            }
            """,
            expected: .missingExclusionReason("excluded")
        )
    }

    private func assertManifestError(
        _ json: String,
        expected: PrivateImageScenarioManifestError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try PrivateImageScenarioManifest.decode(data: Data(json.utf8)),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? PrivateImageScenarioManifestError, expected, file: file, line: line)
        }
    }
}
