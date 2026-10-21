import CoreImage
import Darwin
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

    /// The calibrated simulator enforces the five-second first-prefill NFR by default.
    /// Hosted CI may declare a slower, explicit regression ceiling because Vision throughput
    /// varies with the shared runner; the full private OCR corpus is covered separately.
    @MainActor
    func testPreparationPerformanceAndMemoryStayWithinV2Budget() throws {
        let p95LimitSeconds = try performanceP95LimitSeconds()
        let images = [
            receiptImage(size: CGSize(width: 1_600, height: 1_200)),
            clusterImage(size: CGSize(width: 1_600, height: 1_200)),
            receiptImage(size: CGSize(width: 1_200, height: 1_600))
        ]
        let imageCounts = [1, 2, 3]
        var measurements: [(count: Int, p50: Double, p95: Double, peakDeltaBytes: UInt64)] = []

        for count in imageCounts {
            // Warm Core Image once; subsequent samples represent the user-visible steady path.
            try prepare(images: Array(images.prefix(count)))
            let baselineMemory = residentMemoryBytes()
            var samples: [Double] = []
            var peakMemory = baselineMemory
            for _ in 0..<11 {
                let start = DispatchTime.now().uptimeNanoseconds
                try prepare(images: Array(images.prefix(count))) {
                    peakMemory = max(peakMemory, self.residentMemoryBytes())
                }
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
                samples.append(elapsed)
                peakMemory = max(peakMemory, residentMemoryBytes())
            }
            measurements.append((count, percentile(samples, 0.50), percentile(samples, 0.95),
                                 peakMemory >= baselineMemory ? peakMemory - baselineMemory : 0))
        }

        for measurement in measurements {
            print(String(format: "T22 capture preparation: %d image(s), p50 %.3fs, p95 %.3fs, peak +%.1f MB (limit %.1fs)",
                         measurement.count, measurement.p50, measurement.p95,
                         Double(measurement.peakDeltaBytes) / 1_000_000, p95LimitSeconds))
            XCTAssertLessThanOrEqual(measurement.p95, p95LimitSeconds,
                                     "The p95 exceeded the declared simulator performance limit.")
            XCTAssertLessThanOrEqual(measurement.peakDeltaBytes, 160_000_000,
                                     "Preparation must not retain an unbounded image batch in memory.")
        }
        let report = measurements.map {
            String(format: "%d image(s): p50 %.3fs, p95 %.3fs, peak +%.1f MB",
                   $0.count, $0.p50, $0.p95, Double($0.peakDeltaBytes) / 1_000_000)
        }.joined(separator: "\n")
        let attachment = XCTAttachment(string: report)
        attachment.name = "T22 capture preparation budget"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAnnualLocalEvidenceBudgetUsesVerifiedPerPhotoLimit() {
        let retainedPhotosPerWeek = 10 // five captures, receipt + dashboard photo
        let annualBytes = retainedPhotosPerWeek * 52 * CapturePhotoStore.maxOptimizedByteCount
        XCTAssertEqual(annualBytes, 234_000_000)
        XCTAssertLessThanOrEqual(annualBytes, 250_000_000)
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

    private func clusterImage(size: CGSize = CGSize(width: 400, height: 400)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.red.setFill()
            for column in 0..<16 {
                context.fill(CGRect(x: size.width * 0.09 + CGFloat(column) * size.width * 0.055,
                                    y: size.height * 0.45,
                                    width: size.width * 0.022, height: size.height * 0.112))
            }
        }
    }

    @MainActor
    private func prepare(images: [UIImage], onImagePrepared: (() -> Void)? = nil) throws {
        for (offset, image) in images.enumerated() {
            let kind: CaptureImageKind = offset == 0 ? .invoice : .odometer
            let preparation = try pipeline.prepare(image, declaredKind: kind)
            XCTAssertFalse(preparation.variants.isEmpty)
            onImagePrepared?()
        }
    }

    private func percentile(_ values: [Double], _ quantile: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * quantile).rounded(.up))))
        return sorted[index]
    }

    private func performanceP95LimitSeconds() throws -> Double {
        guard let configuredLimit = ProcessInfo.processInfo.environment["CARTRACK_PERFORMANCE_P95_SECONDS"] else {
            return 5.0
        }
        guard let limit = Double(configuredLimit), limit > 0 else {
            throw NSError(domain: "CaptureImagePipelineTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "CARTRACK_PERFORMANCE_P95_SECONDS must be a positive number."])
        }
        return limit
    }

    private func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
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
