import CoreImage
import Foundation
import UIKit

enum CaptureImageClassificationKind: String, Equatable {
    case invoice
    case odometer
    case fuelLevel
    case other

    init(_ declared: CaptureImageKind) {
        switch declared {
        case .invoice: self = .invoice
        case .odometer: self = .odometer
        case .fuelLevel: self = .fuelLevel
        }
    }
}

enum CaptureImageIssue: String, Equatable {
    case lowResolution = "image.lowResolution"
    case tooBlurred = "image.tooBlurred"
    case overexposed = "image.overexposed"
    case underexposed = "image.underexposed"
    case orientationCorrected = "image.orientationCorrected"
    case possibleGlare = "image.possibleGlare"
    case possibleCrop = "image.possibleCrop"
    case wrongKind = "image.wrongKind"
}

struct CaptureImageQuality: Equatable {
    let pixelWidth: Int
    let pixelHeight: Int
    let blurScore: Double
    let meanBrightness: Double
    let contrast: Double
    let brightNeutralFraction: Double
    let darkFraction: Double
    let redFraction: Double
    let borderInkFraction: Double
    let issues: [CaptureImageIssue]
}

struct CaptureImageClassification: Equatable {
    let kind: CaptureImageClassificationKind
    let confidence: Double
    let reliedOnDeclaredKind: Bool
}

enum CaptureImageVariantKind: String, Equatable {
    case normalized
    case highContrast
    case monochrome
    case redDisplay
}

struct CaptureImageVariant {
    let kind: CaptureImageVariantKind
    let image: CGImage
}

struct CaptureImagePreparation {
    let quality: CaptureImageQuality
    let classification: CaptureImageClassification
    let variants: [CaptureImageVariant]
}

enum CaptureImagePipelineError: Error, Equatable {
    case unreadableImage
}

/// Local, bounded preparation. No pixel data or variant is written to disk.
struct CaptureImagePipeline {
    private static let sampleSide = 96
    private static let maxVariantSide = 2_200
    private static let ciContext = CIContext()

    func prepare(_ image: UIImage, declaredKind: CaptureImageKind? = nil) throws -> CaptureImagePreparation {
        guard let normalized = image.normalizedCGImageForOCR(),
              let sample = PixelSample(image: normalized, side: Self.sampleSide) else {
            throw CaptureImagePipelineError.unreadableImage
        }
        let metrics = sample.metrics
        let classification = classify(metrics: metrics, declaredKind: declaredKind)
        var issues: [CaptureImageIssue] = []
        if normalized.width < 300 || normalized.height < 300 { issues.append(.lowResolution) }
        if metrics.blurScore < 0.005 && metrics.contrast > 0.08 { issues.append(.tooBlurred) }
        if metrics.meanBrightness > 0.93 && metrics.contrast < 0.12 { issues.append(.overexposed) }
        if metrics.meanBrightness < 0.08 && metrics.contrast < 0.12 { issues.append(.underexposed) }
        if image.imageOrientation != .up { issues.append(.orientationCorrected) }
        if (classification.kind == .odometer || classification.kind == .fuelLevel)
            && metrics.brightNeutralFraction > 0.08 && metrics.darkFraction > 0.35 {
            issues.append(.possibleGlare)
        }
        if classification.kind == .invoice && metrics.borderInkFraction > 0.32 {
            issues.append(.possibleCrop)
        }
        if let declaredKind, classification.kind != .other,
           classification.kind.rawValue != declaredKind.rawValue, classification.confidence >= 0.75 {
            issues.append(.wrongKind)
        }
        let quality = CaptureImageQuality(pixelWidth: normalized.width,
                                          pixelHeight: normalized.height,
                                          blurScore: metrics.blurScore,
                                          meanBrightness: metrics.meanBrightness,
                                          contrast: metrics.contrast,
                                          brightNeutralFraction: metrics.brightNeutralFraction,
                                          darkFraction: metrics.darkFraction,
                                          redFraction: metrics.redFraction,
                                          borderInkFraction: metrics.borderInkFraction,
                                          issues: issues)
        return CaptureImagePreparation(quality: quality, classification: classification,
                                       variants: variants(from: normalized, kind: classification.kind))
    }

    private func classify(metrics: PixelMetrics, declaredKind: CaptureImageKind?) -> CaptureImageClassification {
        if metrics.brightNeutralFraction >= 0.50 && metrics.darkFraction < 0.35 {
            return CaptureImageClassification(kind: .invoice, confidence: 0.88,
                                              reliedOnDeclaredKind: false)
        }
        let clusterLike = (metrics.darkFraction >= 0.43 && metrics.redFraction >= 0.015)
            || (metrics.darkFraction >= 0.65 && metrics.brightNeutralFraction < 0.20)
        if clusterLike {
            if let declaredKind, declaredKind == .odometer || declaredKind == .fuelLevel {
                return CaptureImageClassification(kind: CaptureImageClassificationKind(declaredKind), confidence: 0.70,
                                                  reliedOnDeclaredKind: true)
            }
            return CaptureImageClassification(kind: .other, confidence: 0.35,
                                              reliedOnDeclaredKind: false)
        }
        if let declaredKind {
            return CaptureImageClassification(kind: CaptureImageClassificationKind(declaredKind), confidence: 0.40,
                                              reliedOnDeclaredKind: true)
        }
        return CaptureImageClassification(kind: .other, confidence: 0.25,
                                          reliedOnDeclaredKind: false)
    }

    private func variants(from normalized: CGImage, kind: CaptureImageClassificationKind) -> [CaptureImageVariant] {
        let maxSide = max(normalized.width, normalized.height)
        let scale = min(1.0, Double(Self.maxVariantSide) / Double(maxSide))
        let source = CIImage(cgImage: normalized)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        var output: [CaptureImageVariant] = []
        func append(_ kind: CaptureImageVariantKind, _ ciImage: CIImage) {
            if let rendered = Self.ciContext.createCGImage(ciImage, from: ciImage.extent) {
                output.append(CaptureImageVariant(kind: kind, image: rendered))
            }
        }
        append(.normalized, source)
        append(.highContrast, source.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 1.65, kCIInputSaturationKey: 1.0
        ]))
        append(.monochrome, source.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 2.0, kCIInputSaturationKey: 0.0
        ]))
        if kind == .odometer || kind == .fuelLevel {
            append(.redDisplay, source.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            ]))
        }
        return output
    }
}

private struct PixelMetrics {
    let blurScore: Double
    let meanBrightness: Double
    let contrast: Double
    let brightNeutralFraction: Double
    let darkFraction: Double
    let redFraction: Double
    let borderInkFraction: Double
}

private struct PixelSample {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(image: CGImage, side: Int) {
        let ratio = Double(image.width) / Double(max(image.height, 1))
        let sampleWidth = max(8, Int(Double(side) * min(1, ratio)))
        let sampleHeight = max(8, Int(Double(side) / max(1, ratio)))
        var storage = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        let drawn = storage.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: sampleWidth, height: sampleHeight,
                                          bitsPerComponent: 8, bytesPerRow: sampleWidth * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
            return true
        }
        guard drawn else { return nil }
        width = sampleWidth
        height = sampleHeight
        bytes = storage
    }

    var metrics: PixelMetrics {
        let count = width * height
        var luma = [Double](repeating: 0, count: count)
        var sum = 0.0
        var sumSquares = 0.0
        var neutral = 0
        var dark = 0
        var red = 0
        var borderInk = 0
        var borderPixels = 0
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let base = index * 4
                let r = Double(bytes[base]) / 255
                let g = Double(bytes[base + 1]) / 255
                let b = Double(bytes[base + 2]) / 255
                let value = 0.2126 * r + 0.7152 * g + 0.0722 * b
                luma[index] = value
                sum += value
                sumSquares += value * value
                if value > 0.75 && max(r, g, b) - min(r, g, b) < 0.18 { neutral += 1 }
                if value < 0.30 { dark += 1 }
                if r > 0.35 && r > g * 1.45 && r > b * 1.35 { red += 1 }
                if x < 2 || y < 2 || x >= width - 2 || y >= height - 2 {
                    borderPixels += 1
                    if value < 0.45 { borderInk += 1 }
                }
            }
        }
        let average = sum / Double(count)
        let contrast = sqrt(max(0, sumSquares / Double(count) - average * average))
        var laplacianSquares = 0.0
        var laplacianCount = 0
        if width > 2 && height > 2 {
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let index = y * width + x
                    let laplacian = 4 * luma[index] - luma[index - 1] - luma[index + 1]
                        - luma[index - width] - luma[index + width]
                    laplacianSquares += laplacian * laplacian
                    laplacianCount += 1
                }
            }
        }
        return PixelMetrics(blurScore: laplacianSquares / Double(max(laplacianCount, 1)),
                            meanBrightness: average, contrast: contrast,
                            brightNeutralFraction: Double(neutral) / Double(count),
                            darkFraction: Double(dark) / Double(count),
                            redFraction: Double(red) / Double(count),
                            borderInkFraction: Double(borderInk) / Double(max(borderPixels, 1)))
    }
}
