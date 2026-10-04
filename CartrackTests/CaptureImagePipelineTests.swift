import CoreImage
import UIKit
import XCTest
@testable import Cartrack

final class CaptureImagePipelineTests: XCTestCase {
    private let pipeline = CaptureImagePipeline()

    func testReceiptClassificationOverridesWrongDeclaredKindWithoutRejectingWhitePaper() throws {
        let image = receiptImage()
        let prepared = try pipeline.prepare(image, declaredKind: .odometer)

        XCTAssertEqual(prepared.classification.kind, .invoice)
        XCTAssertFalse(prepared.classification.reliedOnDeclaredKind)
        XCTAssertTrue(prepared.quality.issues.contains(.wrongKind))
        XCTAssertFalse(prepared.quality.issues.contains(.overexposed))
        XCTAssertEqual(prepared.variants.map(\.kind), [.normalized, .highContrast, .monochrome])
    }

    func testClusterUsesDeclaredFieldButDoesNotGuessAnalogOrDigitalWithoutIt() throws {
        let image = clusterImage()
        let odometer = try pipeline.prepare(image, declaredKind: .odometer)
        let gauge = try pipeline.prepare(image, declaredKind: .fuelLevel)
        let unknown = try pipeline.prepare(image)

        XCTAssertEqual(odometer.classification.kind, .odometer)
        XCTAssertEqual(gauge.classification.kind, .fuelLevel)
        XCTAssertTrue(odometer.classification.reliedOnDeclaredKind)
        XCTAssertEqual(unknown.classification.kind, .other)
        XCTAssertEqual(odometer.variants.last?.kind, .redDisplay)
    }

    func testBlurAndExposureProduceRecoverableQualityIssues() throws {
        let sharp = receiptImage()
        let blurred = try XCTUnwrap(blur(sharp, radius: 14))
        let sharpResult = try pipeline.prepare(sharp, declaredKind: .invoice)
        let blurredResult = try pipeline.prepare(blurred, declaredKind: .invoice)
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        }
        let blankResult = try pipeline.prepare(blank, declaredKind: .invoice)

        XCTAssertGreaterThan(sharpResult.quality.blurScore, blurredResult.quality.blurScore)
        XCTAssertFalse(sharpResult.quality.issues.contains(.tooBlurred),
                       "sharp score: \(sharpResult.quality.blurScore)")
        XCTAssertTrue(blurredResult.quality.issues.contains(.tooBlurred),
                      "blur score: \(blurredResult.quality.blurScore)")
        XCTAssertTrue(blankResult.quality.issues.contains(.overexposed))
    }

    func testGlareCropAndDarkExposureHaveDistinctRecoverableIssues() throws {
        let glare = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { context in
            clusterImage().draw(in: CGRect(x: 0, y: 0, width: 400, height: 400))
            UIColor.white.setFill()
            context.fill(CGRect(x: 130, y: 120, width: 135, height: 135))
        }
        let cropped = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { context in
            receiptImage().draw(in: CGRect(x: 0, y: 0, width: 400, height: 400))
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 14))
            context.fill(CGRect(x: 0, y: 386, width: 400, height: 14))
        }
        let black = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        }

        XCTAssertTrue(try pipeline.prepare(glare, declaredKind: .odometer)
            .quality.issues.contains(.possibleGlare))
        XCTAssertTrue(try pipeline.prepare(cropped, declaredKind: .invoice)
            .quality.issues.contains(.possibleCrop))
        XCTAssertTrue(try pipeline.prepare(black)
            .quality.issues.contains(.underexposed))
    }

    func testOrientationIsNormalizedAndVariantsAreBoundedInMemory() throws {
        let source = receiptImage(size: CGSize(width: 3_000, height: 600))
        let rotated = try XCTUnwrap(source.cgImage.map {
            UIImage(cgImage: $0, scale: 1, orientation: .right)
        })
        let result = try pipeline.prepare(rotated, declaredKind: .invoice)

        XCTAssertEqual(result.quality.pixelWidth, source.cgImage?.height)
        XCTAssertEqual(result.quality.pixelHeight, source.cgImage?.width)
        XCTAssertTrue(result.quality.issues.contains(.orientationCorrected))
        XCTAssertFalse(result.variants.isEmpty)
        for variant in result.variants {
            XCTAssertLessThanOrEqual(max(variant.image.width, variant.image.height), 2_200)
        }
    }

    func testTinyImageIsFlaggedWithoutCrashing() throws {
        let tiny = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        let result = try pipeline.prepare(tiny)
        XCTAssertTrue(result.quality.issues.contains(.lowResolution))
    }

    private func receiptImage(size: CGSize = CGSize(width: 400, height: 400)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            for row in 0..<12 {
                context.fill(CGRect(x: size.width * 0.15,
                                    y: size.height * (0.15 + Double(row) * 0.055),
                                    width: size.width * 0.65, height: max(3, size.height * 0.012)))
            }
        }
    }

    private func clusterImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            UIColor.red.setFill()
            for column in 0..<16 {
                context.fill(CGRect(x: 35 + column * 22, y: 180,
                                    width: 9, height: 45))
            }
        }
    }

    private func blur(_ image: UIImage, radius: Double) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let source = CIImage(cgImage: cgImage)
        let filtered = source.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: source.extent)
        guard let result = CIContext().createCGImage(filtered, from: source.extent) else { return nil }
        return UIImage(cgImage: result)
    }
}
