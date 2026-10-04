import CryptoKit
import SwiftData
import UIKit
import XCTest
@testable import Cartrack

@MainActor
final class FuelCaptureWorkflowTests: XCTestCase {
    func testThreePhotosProduceRecoverableReviewedDraftAndLocalEvidence() async throws {
        try await withStore { container, support, photoRoot, vehicle in
            let workflow = makeWorkflow(container: container, photoRoot: photoRoot,
                                        recognized: completeReading())
            let input = makeInput(vehicle: vehicle, images: images())
            let outcome = try await workflow.analyze(input: input)

            XCTAssertEqual(outcome.session.state, .review)
            XCTAssertEqual(outcome.session.draft.volumeGallons, 11)
            XCTAssertEqual(outcome.session.draft.unitPrice, 43)
            XCTAssertEqual(outcome.session.draft.totalCost, 473)
            XCTAssertNotNil(outcome.session.draft.odometerKilometers)
            XCTAssertNotNil(outcome.session.draft.tripKilometers)
            XCTAssertNil(outcome.session.draft.fuelLevelRemaining,
                         "An analog gauge must not be auto-filled before calibration")
            XCTAssertEqual(outcome.session.draft.photoIDs.count, 3)
            XCTAssertEqual(outcome.fields.first { $0.field == .totalCost }?.band, .medium)

            let photoRepo = SwiftDataPhotoAssetRepository(context: ModelContext(container))
            let savedPhotos = try await photoRepo.all(sessionID: outcome.session.id)
            XCTAssertEqual(savedPhotos.count, 3)
            for photo in savedPhotos {
                XCTAssertFalse(photo.localRelativePath.hasPrefix("/"))
                XCTAssertGreaterThan(photo.byteCount, 0)
                let image = try CapturePhotoStore(rootURL: photoRoot).load(photo)
                XCTAssertNotNil(image.cgImage)
                let bytes = try Data(contentsOf: photoRoot.appendingPathComponent(photo.localRelativePath))
                let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                XCTAssertEqual(photo.sha256, digest)
            }
            let evidence = try await SwiftDataOCRFieldEvidenceRepository(context: ModelContext(container))
                .all(sessionID: outcome.session.id)
            XCTAssertEqual(evidence.count, 6)
            XCTAssertTrue(evidence.allSatisfy { $0.ownerEventID == nil && $0.sourcePhotoID != nil })

            let reopened = try CartrackModelContainer.make(applicationSupportURL: support,
                                                            legacyStoreURL: support.appendingPathComponent("unused-v1.store"))
            let reopenedSession = try await SwiftDataCaptureSessionRepository(container: reopened)
                .find(id: outcome.session.id)
            XCTAssertEqual(reopenedSession?.state, .review)
            XCTAssertEqual(reopenedSession?.draft, outcome.session.draft)
        }
    }

    func testReanalysisReusesSavedPhotosAfterRelaunchWithoutDuplicatingAssets() async throws {
        try await withStore { container, support, photoRoot, vehicle in
            let workflow = makeWorkflow(container: container, photoRoot: photoRoot,
                                        recognized: completeReading())
            let created = try await workflow.analyze(input: makeInput(vehicle: vehicle, images: images()))
            let reopened = try CartrackModelContainer.make(applicationSupportURL: support,
                                                            legacyStoreURL: support.appendingPathComponent("unused-v1.store"))
            let retry = makeWorkflow(container: reopened, photoRoot: photoRoot,
                                     recognized: completeReading())
            let reviewed = try await retry.analyze(input: makeInput(vehicle: vehicle, images: [:]),
                                                    sessionID: created.session.id)
            XCTAssertEqual(reviewed.session.state, .review)
            XCTAssertEqual(reviewed.session.draft.photoIDs, created.session.draft.photoIDs)
            let photos = try await SwiftDataPhotoAssetRepository(context: ModelContext(reopened))
                .all(sessionID: created.session.id)
            XCTAssertEqual(photos.count, 3)
        }
    }

    func testReanalysisWithUnchangedPickerImagesDoesNotDuplicatePhotoRecords() async throws {
        try await withStore { container, _, photoRoot, vehicle in
            let workflow = makeWorkflow(container: container, photoRoot: photoRoot,
                                        recognized: completeReading())
            let selectedImages = images()
            let first = try await workflow.analyze(input: makeInput(vehicle: vehicle,
                                                                     images: selectedImages))
            let second = try await workflow.analyze(input: makeInput(vehicle: vehicle,
                                                                      images: selectedImages),
                                                    sessionID: first.session.id)
            XCTAssertEqual(second.session.draft.photoIDs, first.session.draft.photoIDs)
            let stored = try await SwiftDataPhotoAssetRepository(context: ModelContext(container))
                .all(sessionID: first.session.id)
            XCTAssertEqual(stored.count, 3)
        }
    }

    func testFinancialConflictDoesNotPrefillUnverifiedAmounts() async throws {
        try await withStore { container, _, photoRoot, vehicle in
            var reading = completeReading()
            reading.totalCost = 450
            let workflow = makeWorkflow(container: container, photoRoot: photoRoot, recognized: reading)
            let outcome = try await workflow.analyze(input: makeInput(vehicle: vehicle, images: images()))
            XCTAssertNil(outcome.session.draft.volumeGallons)
            XCTAssertNil(outcome.session.draft.unitPrice)
            XCTAssertNil(outcome.session.draft.totalCost)
            XCTAssertEqual(outcome.fields.first { $0.field == .totalCost }?.band, .critical)
            XCTAssertTrue(outcome.fields.first { $0.field == .totalCost }?
                .validationCodes.contains("field.financialMismatch") == true)
        }
    }

    func testNoPhotosLeavesRequiredFieldsManualAndSessionRecoverable() async throws {
        try await withStore { container, _, photoRoot, vehicle in
            let workflow = makeWorkflow(container: container, photoRoot: photoRoot,
                                        recognized: completeReading())
            let outcome = try await workflow.analyze(input: makeInput(vehicle: vehicle, images: [:]))
            XCTAssertEqual(outcome.session.state, .review)
            XCTAssertTrue(outcome.session.draft.photoIDs.isEmpty)
            XCTAssertNil(outcome.session.draft.totalCost)
            XCTAssertEqual(outcome.fields.first { $0.field == .totalCost }?.band, .critical)
        }
    }

    func testPhotoStoreRejectsTraversalAndCanRemoveOnlyItsOwnAsset() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CartrackPhotoStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CapturePhotoStore(rootURL: root)
        let record = try store.save(images()[.invoice]!, sessionID: UUID(), kind: .invoice)
        XCTAssertNotNil(try store.load(record).cgImage)
        var invalid = record
        invalid.localRelativePath = "../outside.jpg"
        XCTAssertThrowsError(try store.load(invalid))
        XCTAssertThrowsError(try store.remove(invalid))
        invalid = record
        invalid.sessionID = UUID()
        XCTAssertThrowsError(try store.load(invalid))
        let photoURL = root.appendingPathComponent(record.localRelativePath)
        try Data("tampered".utf8).write(to: photoURL, options: .atomic)
        XCTAssertThrowsError(try store.load(record)) { error in
            guard case CapturePhotoStoreError.integrityMismatch = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
        try store.remove(record)
        XCTAssertThrowsError(try store.load(record))
    }

    private func withStore(_ body: (ModelContainer, URL, URL, Vehicle) async throws -> Void) async throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("CartrackFuelCaptureTests-\(UUID().uuidString)", isDirectory: true)
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
                              recognized: FillUpPrefill) -> FuelCaptureWorkflow {
        FuelCaptureWorkflow(
            sessions: SwiftDataCaptureSessionRepository(container: container),
            photos: SwiftDataPhotoAssetRepository(context: ModelContext(container)),
            evidence: SwiftDataOCRFieldEvidenceRepository(context: ModelContext(container)),
            photoStore: CapturePhotoStore(rootURL: photoRoot),
            recognizer: FixedFuelRecognizer(result: recognized)
        )
    }

    private func makeInput(vehicle: Vehicle, images: [CaptureImageKind: UIImage]) -> FuelCaptureInput {
        FuelCaptureInput(vehicleID: vehicle.id, occurredAt: .now, odometerUnit: .miles,
                         tankCapacityGallons: 14, fuelScaleMax: 8, fuelScaleStep: 0.25,
                         previousOdometerKilometers: nil,
                         lastFillOdometerKilometers: nil,
                         previousClusterReading: nil, images: images)
    }

    private func completeReading() -> FillUpPrefill {
        var result = FillUpPrefill()
        result.invoiceText = "11 gal, Q43, Q473"
        result.odometerText = "108749 miles 587.3"
        result.fuelLevelText = "2 spaces"
        result.gallons = 11
        result.pricePerGallon = 43
        result.totalCost = 473
        result.odometerMiles = 108_749
        result.tripMiles = 587.3
        result.fuelLevelRemaining = 2
        return result
    }

    private func images() -> [CaptureImageKind: UIImage] {
        let invoice = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            UIColor.black.setFill()
            for row in 0..<12 {
                context.fill(CGRect(x: 60, y: 60 + row * 20, width: 280, height: 5))
            }
        }
        let cluster = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            UIColor.red.setFill()
            for column in 0..<16 {
                context.fill(CGRect(x: 35 + column * 22, y: 180, width: 9, height: 45))
            }
        }
        return [.invoice: invoice, .odometer: cluster, .fuelLevel: cluster]
    }
}

private struct FixedFuelRecognizer: FuelCaptureRecognizing {
    let result: FillUpPrefill

    func analyzeFillUp(invoiceImage: UIImage?, odometerImage: UIImage?, fuelLevelImage: UIImage?,
                       fuelScaleMax: Double,
                       previousClusterReading: InstrumentClusterReading?) async -> FillUpPrefill {
        result
    }
}
