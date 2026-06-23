import Foundation
import CoreImage
import UIKit
@preconcurrency import Vision

protocol OCRTextRecognizing: Sendable {
    func recognizeText(from image: UIImage?) async -> String
    func recognizeInstrumentClusterText(from image: UIImage?) async -> String
}

struct VisionOCRTextRecognizer: OCRTextRecognizing {
    private static let ciContext = CIContext()

    func recognizeText(from image: UIImage?) async -> String {
        guard let cgImage = image?.cgImage else { return "" }
        return await recognize(cgImage: cgImage)
    }

    func recognizeInstrumentClusterText(from image: UIImage?) async -> String {
        guard let cgImage = image?.cgImage else { return "" }
        let standardText = await recognize(cgImage: cgImage)
        let enhancedTexts = await instrumentClusterVariants(from: cgImage).asyncMap { variant in
            await recognize(cgImage: variant)
        }

        return ([standardText] + enhancedTexts)
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func recognize(cgImage: CGImage) async -> String {
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil else {
                    continuation.resume(returning: "")
                    return
                }
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "")
            }
        }
    }

    private func instrumentClusterVariants(from cgImage: CGImage) -> [CGImage] {
        let normalizedCrops: [CGRect] = [
            CGRect(x: 0.16, y: 0.55, width: 0.55, height: 0.25),
            CGRect(x: 0.18, y: 0.57, width: 0.47, height: 0.18),
            CGRect(x: 0.18, y: 0.56, width: 0.43, height: 0.11),
        ]

        return normalizedCrops
            .compactMap { crop(cgImage, normalizedRect: $0) }
            .flatMap { crop in
                [
                    enhanced(crop, exposure: 1.5, contrast: 3.0, grayscale: false, inverted: false),
                    enhanced(crop, exposure: 1.5, contrast: 4.0, grayscale: true, inverted: true),
                ].compactMap { $0 }
            }
    }

    private func crop(_ cgImage: CGImage, normalizedRect: CGRect) -> CGImage? {
        let rect = CGRect(
            x: CGFloat(cgImage.width) * normalizedRect.minX,
            y: CGFloat(cgImage.height) * normalizedRect.minY,
            width: CGFloat(cgImage.width) * normalizedRect.width,
            height: CGFloat(cgImage.height) * normalizedRect.height
        ).integral
        return cgImage.cropping(to: rect)
    }

    private func enhanced(_ cgImage: CGImage, exposure: Double, contrast: Double, grayscale: Bool, inverted: Bool) -> CGImage? {
        var image = CIImage(cgImage: cgImage)
        image = image.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputContrastKey: contrast,
                kCIInputSaturationKey: grayscale ? 0 : 1,
            ]
        )
        image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposure])
        if inverted {
            image = image.applyingFilter("CIColorInvert")
        }
        return Self.ciContext.createCGImage(image, from: image.extent)
    }
}

struct FillUpPrefill {
    var invoiceText: String = ""
    var odometerText: String = ""
    var fuelLevelText: String = ""
    var gallons: Double?
    var pricePerGallon: Double?
    var totalCost: Double?
    var odometerMiles: Double?
    var tripMiles: Double?
    var fuelLevelRemaining: Double?
}

struct SnapshotPrefill {
    var odometerText: String = ""
    var fuelLevelText: String = ""
    var odometerMiles: Double?
    var tripMiles: Double?
    var fuelLevelRemaining: Double?
}

final class OCRService: @unchecked Sendable {
    private let parser: OCRTextParser
    private let recognizer: OCRTextRecognizing

    init(parser: OCRTextParser = OCRTextParser(), recognizer: OCRTextRecognizing = VisionOCRTextRecognizer()) {
        self.parser = parser
        self.recognizer = recognizer
    }

    func analyzeFillUp(
        invoiceImage: UIImage?,
        odometerImage: UIImage?,
        fuelLevelImage: UIImage?,
        fuelScaleMax: Double
    ) async -> FillUpPrefill {
        async let invoiceText = recognizer.recognizeText(from: invoiceImage)
        async let odometerText = recognizer.recognizeInstrumentClusterText(from: odometerImage)
        async let fuelLevelText = recognizer.recognizeText(from: fuelLevelImage)

        let invoice = await invoiceText
        let odometer = await odometerText
        let fuelLevel = await fuelLevelText
        let parsed = parser.parseFillUp(
            invoiceText: invoice,
            odometerText: odometer,
            fuelLevelText: fuelLevel,
            fuelScaleMax: fuelScaleMax
        )

        return FillUpPrefill(
            invoiceText: invoice,
            odometerText: odometer,
            fuelLevelText: fuelLevel,
            gallons: parsed.gallons,
            pricePerGallon: parsed.pricePerGallon,
            totalCost: parsed.totalCost,
            odometerMiles: parsed.odometerMiles,
            tripMiles: parsed.tripMiles,
            fuelLevelRemaining: parsed.fuelLevelRemaining
        )
    }

    func analyzeSnapshot(
        odometerImage: UIImage?,
        fuelLevelImage: UIImage?,
        fuelScaleMax: Double
    ) async -> SnapshotPrefill {
        async let odometerText = recognizer.recognizeInstrumentClusterText(from: odometerImage)
        async let fuelLevelText = recognizer.recognizeText(from: fuelLevelImage)

        let odometer = await odometerText
        let fuelLevel = await fuelLevelText
        let parsed = parser.parseSnapshot(
            odometerText: odometer,
            fuelLevelText: fuelLevel,
            fuelScaleMax: fuelScaleMax
        )

        return SnapshotPrefill(
            odometerText: odometer,
            fuelLevelText: fuelLevel,
            odometerMiles: parsed.odometerMiles,
            tripMiles: parsed.tripMiles,
            fuelLevelRemaining: parsed.fuelLevelRemaining
        )
    }

}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var values: [T] = []
        values.reserveCapacity(count)
        for element in self {
            let value = await transform(element)
            values.append(value)
        }
        return values
    }
}
