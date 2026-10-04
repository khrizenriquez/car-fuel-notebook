import SwiftData
import UIKit
import XCTest
@testable import Cartrack

@MainActor
final class SnapshotCaptureWorkflowTests: XCTestCase {
    func testTwoPhotosPrefillOdometerAndTripButNotAnalogFuel() async throws {
        try await withStore { container, _, photoRoot, vehicle in
            let workflow = makeWorkflow(container: container, photoRoot: photoRoot,
                                        recognized: reading())
            let outcome = try await workflow.analyze(input: input(vehicle: vehicle, images: images()))
            XCTAssertEqual(outcome.session.kind, .snapshot)
            XCTAssertEqual(outcome.session.state, .review)
            XCTAssertEqual(outcome.session.draft.photoIDs.count, 2)
            XCTAssertNotNil(outcome.session.draft.odometerKilometers)
            XCTAssertNotNil(outcome.session.draft.tripKilometers)
            XCTAssertNil(outcome.session.draft.fuelLevelRemaining)
            XCTAssertNil(outcome.session.draft.totalCost)
            XCTAssertEqual(outcome.fields.first { $0.field == .odometerKilometers }?.band, .medium)
            XCTAssertEqual(outcome.fields.first { $0.field == .fuelLevelRemaining }?.band, .low)
            let evidence = try await SwiftDataOCRFieldEvidenceRepository(context: ModelContext(container))
                .all(sessionID: outcome.session.id)
            XCTAssertEqual(evidence.count, 3)
            XCTAssertTrue(evidence.allSatisfy { $0.sourcePhotoID != nil })
        }
    }

    func testSnapshotRelaunchReusesLocalPhotosAndKeepsDraft() async throws {
        try await withStore { container, support, photoRoot, vehicle in
            let first = makeWorkflow(container: container, photoRoot: photoRoot,
                                     recognized: reading())
            let created = try await first.analyze(input: input(vehicle: vehicle, images: images()))
            let reopened = try CartrackModelContainer.make(applicationSupportURL: support,
                                                            legacyStoreURL: support.appendingPathComponent("unused-v1.store"))
            let second = makeWorkflow(container: reopened, photoRoot: photoRoot,
                                      recognized: reading())
            let resumed = try await second.analyze(input: input(vehicle: vehicle, images: [:]),
                                                   sessionID: created.session.id)
            XCTAssertEqual(resumed.session.state, .review)
            XCTAssertEqual(resumed.session.draft.photoIDs, created.session.draft.photoIDs)
            XCTAssertEqual(resumed.images.count, 2)
            let saved = try await SwiftDataPhotoAssetRepository(context: ModelContext(reopened))
                .all(sessionID: created.session.id)
            XCTAssertEqual(saved.count, 2)
        }
    }

    func testOptionalTripCanBeMissingAndOdometerCanFallBackToManual() async throws {
        try await withStore { container, _, photoRoot, vehicle in
            var partial = SnapshotPrefill()
            partial.odometerMiles = 108_768
            let workflow = makeWorkflow(container: container, photoRoot: photoRoot, recognized: partial)
            let withOdometer = try await workflow.analyze(input: input(vehicle: vehicle,
                                                                        images: images()))
            XCTAssertNotNil(withOdometer.session.draft.odometerKilometers)
            XCTAssertNil(withOdometer.session.draft.tripKilometers)
            let noPhoto = try await workflow.analyze(input: input(vehicle: vehicle, images: [:]))
            XCTAssertNil(noPhoto.session.draft.odometerKilometers)
            XCTAssertEqual(noPhoto.fields.first { $0.field == .odometerKilometers }?.band, .critical)
        }
    }

    func testSamePickerPhotosDoNotCreateDuplicateAssets() async throws {
        try await withStore { container, _, photoRoot, vehicle in
            let workflow = makeWorkflow(container: container, photoRoot: photoRoot,
                                        recognized: reading())
            let selectedImages = images()
            let first = try await workflow.analyze(input: input(vehicle: vehicle,
                                                                  images: selectedImages))
            let second = try await workflow.analyze(input: input(vehicle: vehicle,
                                                                   images: selectedImages),
                                                    sessionID: first.session.id)
            XCTAssertEqual(second.session.draft.photoIDs, first.session.draft.photoIDs)
            let assets = try await SwiftDataPhotoAssetRepository(context: ModelContext(container))
                .all(sessionID: first.session.id)
            XCTAssertEqual(assets.count, 2)
        }
    }

    func testSessionCannotBeReusedForAnotherVehicle() async throws {
        try await withStore { container, _, photoRoot, vehicle in
            let workflow = makeWorkflow(container: container, photoRoot: photoRoot,
                                        recognized: reading())
            let first = try await workflow.analyze(input: input(vehicle: vehicle, images: [:]))
            let another = Vehicle(name: "Other", make: "Toyota", modelName: "Yaris", year: 2020)
            let context = ModelContext(container)
            context.insert(another)
            try context.save()
            do {
                _ = try await workflow.analyze(input: input(vehicle: another, images: [:]),
                                               sessionID: first.session.id)
                XCTFail("A capture session cannot switch vehicles")
            } catch CaptureSessionError.notFound {}
        }
    }

    func testReplacingOdometerPhotoUpdatesOCRButKeepsManualTrip() async throws {
        try await withStore { container, _, photoRoot, vehicle in
            let firstWorkflow = makeWorkflow(container: container, photoRoot: photoRoot,
                                             recognized: reading())
            let first = try await firstWorkflow.analyze(input: input(vehicle: vehicle, images: images()))
            var corrected = first.session.draft
            let manualTrip = Decimal(string: String(UnitConversion.milesToKilometers(600)))!
            corrected.setManualNumber(manualTrip, for: .tripKilometers)
            let repository = SwiftDataCaptureSessionRepository(container: container)
            _ = try await repository.updateDraft(id: first.session.id,
                                                 expectedRevision: first.session.revision,
                                                 draft: corrected)
            var replacement = SnapshotPrefill()
            replacement.odometerMiles = 108_800
            replacement.tripMiles = 650
            let secondWorkflow = makeWorkflow(container: container, photoRoot: photoRoot,
                                              recognized: replacement)
            let newPhoto = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image {
                UIColor.green.setFill()
                $0.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            }
            let second = try await secondWorkflow.analyze(
                input: input(vehicle: vehicle, images: [.odometer: newPhoto]),
                sessionID: first.session.id
            )
            XCTAssertEqual(second.session.draft.tripKilometers, manualTrip)
            let odometer = try XCTUnwrap(second.session.draft.odometerKilometers)
            XCTAssertEqual(UnitConversion.kilometersToMiles(NSDecimalNumber(decimal: odometer).doubleValue),
                           108_800, accuracy: 1)
            XCTAssertEqual(second.session.draft.photoIDs.count, 3)
        }
    }

    private func withStore(_ body: (ModelContainer, URL, URL, Vehicle) async throws -> Void) async throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("CartrackSnapshotCaptureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let container = try CartrackModelContainer.make(applicationSupportURL: support,
                                                        legacyStoreURL: support.appendingPathComponent("unused-v1.store"))
        let vehicle = Vehicle(name: "Z4", make: "BMW", modelName: "Z4", year: 2003)
        let context = ModelContext(container)
        context.insert(vehicle)
        try context.save()
        try await body(container, support, support.appendingPathComponent("Photos", isDirectory: true), vehicle)
    }

    private func makeWorkflow(container: ModelContainer, photoRoot: URL,
                              recognized: SnapshotPrefill) -> SnapshotCaptureWorkflow {
        SnapshotCaptureWorkflow(
            sessions: SwiftDataCaptureSessionRepository(container: container),
            photos: SwiftDataPhotoAssetRepository(context: ModelContext(container)),
            evidence: SwiftDataOCRFieldEvidenceRepository(context: ModelContext(container)),
            photoStore: CapturePhotoStore(rootURL: photoRoot),
            recognizer: FixedSnapshotRecognizer(result: recognized)
        )
    }

    private func input(vehicle: Vehicle, images: [CaptureImageKind: UIImage]) -> SnapshotCaptureInput {
        SnapshotCaptureInput(vehicleID: vehicle.id, occurredAt: .now,
                             fuelScaleMax: 8, fuelScaleStep: 0.25,
                             previousOdometerKilometers: nil,
                             lastFillOdometerKilometers: nil,
                             previousClusterReading: nil, images: images)
    }

    private func reading() -> SnapshotPrefill {
        var result = SnapshotPrefill()
        result.odometerText = "108768 miles 606.5"
        result.fuelLevelText = "2 spaces"
        result.odometerMiles = 108_768
        result.tripMiles = 606.5
        result.fuelLevelRemaining = 2
        return result
    }

    private func images() -> [CaptureImageKind: UIImage] {
        let cluster = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            UIColor.red.setFill()
            for column in 0..<16 {
                context.fill(CGRect(x: 35 + column * 22, y: 180, width: 9, height: 45))
            }
        }
        return [.odometer: cluster, .fuelLevel: cluster]
    }
}

private struct FixedSnapshotRecognizer: SnapshotCaptureRecognizing {
    let result: SnapshotPrefill

    func analyzeSnapshot(odometerImage: UIImage?, fuelLevelImage: UIImage?, fuelScaleMax: Double,
                         previousClusterReading: InstrumentClusterReading?) async -> SnapshotPrefill {
        result
    }
}
