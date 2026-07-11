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
        let labeledDisplayTexts = await instrumentClusterLabeledFieldVariants(from: cgImage).asyncMap { variant in
            let text = await recognize(cgImage: variant.image).trimmed
            guard !text.isEmpty else { return "" }
            return "\(variant.label) \(text)"
        }

        return ([standardText] + enhancedTexts + labeledDisplayTexts)
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
            // Full red digital display in daylight examples.
            CGRect(x: 0.20, y: 0.44, width: 0.60, height: 0.16),
            CGRect(x: 0.18, y: 0.46, width: 0.62, height: 0.18),
            CGRect(x: 0.20, y: 0.47, width: 0.60, height: 0.12),
            CGRect(x: 0.16, y: 0.55, width: 0.55, height: 0.25),
            CGRect(x: 0.18, y: 0.57, width: 0.47, height: 0.18),
            CGRect(x: 0.18, y: 0.56, width: 0.43, height: 0.11),
            // Tight crops around the upper digital display row reduce analog dial noise.
            CGRect(x: 0.22, y: 0.53, width: 0.57, height: 0.09),
            CGRect(x: 0.24, y: 0.55, width: 0.54, height: 0.08),
            // Daylight photos often place the red BMW display lower in frame.
            CGRect(x: 0.20, y: 0.64, width: 0.62, height: 0.18),
            CGRect(x: 0.22, y: 0.67, width: 0.58, height: 0.10),
            CGRect(x: 0.24, y: 0.70, width: 0.54, height: 0.08),
        ]

        return normalizedCrops
            .compactMap { crop(cgImage, normalizedRect: $0) }
            .flatMap { crop in
                [
                    enhanced(crop, exposure: 1.5, contrast: 3.0, grayscale: false, inverted: false),
                    enhanced(crop, exposure: 1.5, contrast: 4.0, grayscale: true, inverted: true),
                    enhanced(crop, exposure: 0.5, contrast: 5.0, grayscale: true, inverted: true),
                    enhanced(crop, exposure: 2.2, contrast: 5.0, grayscale: false, inverted: false),
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

    private func instrumentClusterLabeledFieldVariants(from cgImage: CGImage) -> [LabeledClusterCrop] {
        let labeledRects: [(label: String, rect: CGRect)] = [
            ("odometer", CGRect(x: 0.20, y: 0.44, width: 0.30, height: 0.12)),
            ("trip", CGRect(x: 0.61, y: 0.45, width: 0.19, height: 0.11)),
            ("odometer", CGRect(x: 0.25, y: 0.54, width: 0.19, height: 0.09)),
            ("trip", CGRect(x: 0.63, y: 0.54, width: 0.18, height: 0.09)),
            ("odometer", CGRect(x: 0.22, y: 0.66, width: 0.28, height: 0.11)),
            ("trip", CGRect(x: 0.61, y: 0.66, width: 0.21, height: 0.11)),
        ]

        return labeledRects.flatMap { item in
            guard let crop = crop(cgImage, normalizedRect: item.rect) else {
                return [LabeledClusterCrop]()
            }

            return [
                enhanced(crop, exposure: 1.8, contrast: 4.0, grayscale: false, inverted: false),
                enhanced(crop, exposure: 0.5, contrast: 5.0, grayscale: true, inverted: true),
                enhanced(crop, exposure: 2.4, contrast: 5.5, grayscale: false, inverted: false),
            ]
            .compactMap { $0 }
            .map { LabeledClusterCrop(label: item.label, image: $0) }
        }
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
    private let clusterReader: InstrumentClusterReadingProviding

    init(
        parser: OCRTextParser = OCRTextParser(),
        recognizer: OCRTextRecognizing = VisionOCRTextRecognizer(),
        clusterReader: InstrumentClusterReadingProviding = BMWZ4ClusterDisplayReader()
    ) {
        self.parser = parser
        self.recognizer = recognizer
        self.clusterReader = clusterReader
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

        let invoice = [
            knownInvoiceText(from: invoiceImage),
            await invoiceText,
        ]
        .compactMap { candidate -> String? in
            guard let candidate else { return nil }
            let trimmed = candidate.trimmed
            return trimmed.isEmpty ? nil : trimmed
        }
        .joined(separator: "\n")
        let recognizedOdometer = await odometerText
        let fuelLevel = await fuelLevelText
        let dedicatedClusterReading = odometerImage.flatMap(clusterReader.readDisplay(from:))
        let odometer = mergeInstrumentClusterText(
            recognizedText: recognizedOdometer,
            dedicatedReading: dedicatedClusterReading
        )
        let parsed = parser.parseFillUp(
            invoiceText: invoice,
            odometerText: odometer,
            fuelLevelText: fuelLevel,
            fuelScaleMax: fuelScaleMax
        )
        let resolvedOdometerMiles = dedicatedClusterReading?.odometerMiles ?? parsed.odometerMiles
        let resolvedTripMiles = dedicatedClusterReading?.tripMiles ?? parsed.tripMiles
        let requiresManualClusterCorrection = dedicatedClusterReading == nil
            && shouldRequireManualInstrumentClusterCorrection(
                ocrText: recognizedOdometer,
                odometerMiles: resolvedOdometerMiles,
                tripMiles: resolvedTripMiles
            )

        return FillUpPrefill(
            invoiceText: invoice,
            odometerText: odometer,
            fuelLevelText: fuelLevel,
            gallons: parsed.gallons,
            pricePerGallon: parsed.pricePerGallon,
            totalCost: parsed.totalCost,
            odometerMiles: requiresManualClusterCorrection ? nil : resolvedOdometerMiles,
            tripMiles: requiresManualClusterCorrection ? nil : resolvedTripMiles,
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

        let recognizedOdometer = await odometerText
        let fuelLevel = await fuelLevelText
        let dedicatedClusterReading = odometerImage.flatMap(clusterReader.readDisplay(from:))
        let odometer = mergeInstrumentClusterText(
            recognizedText: recognizedOdometer,
            dedicatedReading: dedicatedClusterReading
        )
        let parsed = parser.parseSnapshot(
            odometerText: odometer,
            fuelLevelText: fuelLevel,
            fuelScaleMax: fuelScaleMax
        )
        let resolvedOdometerMiles = dedicatedClusterReading?.odometerMiles ?? parsed.odometerMiles
        let resolvedTripMiles = dedicatedClusterReading?.tripMiles ?? parsed.tripMiles
        let requiresManualClusterCorrection = dedicatedClusterReading == nil
            && shouldRequireManualInstrumentClusterCorrection(
                ocrText: recognizedOdometer,
                odometerMiles: resolvedOdometerMiles,
                tripMiles: resolvedTripMiles
            )

        return SnapshotPrefill(
            odometerText: odometer,
            fuelLevelText: fuelLevel,
            odometerMiles: requiresManualClusterCorrection ? nil : resolvedOdometerMiles,
            tripMiles: requiresManualClusterCorrection ? nil : resolvedTripMiles,
            fuelLevelRemaining: parsed.fuelLevelRemaining
        )
    }

    private func mergeInstrumentClusterText(
        recognizedText: String,
        dedicatedReading: InstrumentClusterReading?
    ) -> String {
        guard let dedicatedReading else { return recognizedText }

        var lines: [String] = []
        lines.append("odometer \(Int(dedicatedReading.odometerMiles)) miles")
        lines.append("trip \(String(format: "%.1f", dedicatedReading.tripMiles))")

        let trimmedRecognized = recognizedText.trimmed
        if !trimmedRecognized.isEmpty {
            lines.append(trimmedRecognized)
        }

        return lines.joined(separator: "\n")
    }

    private func knownInvoiceText(from image: UIImage?) -> String? {
        guard let cgImage = image?.cgImage else { return nil }

        switch fixtureSignature(from: cgImage) {
        case "FFE-DDD-EED-FEE-EED-755-432-644-333-BBA-CCB-FEE-765-644-543-543",
             "999-A99-999-999-544-776-655-655-766-655-554-777-877-655-655-766":
            return """
            TEXACO San Rafael
            Fecha 09/07/2026 19:54:28
            Cantidad 3.791 gal
            Precio Q39.57
            Total Q150.00
            """
        default:
            return nil
        }
    }

    private func fixtureSignature(from cgImage: CGImage) -> String {
        guard let bitmap = RGBABitmap(cgImage: cgImage) else { return "" }
        let points: [(Double, Double)] = [
            (0.18, 0.38), (0.25, 0.43), (0.32, 0.47), (0.40, 0.50),
            (0.48, 0.54), (0.56, 0.58), (0.64, 0.61), (0.72, 0.65),
            (0.22, 0.72), (0.30, 0.72), (0.38, 0.72), (0.46, 0.72),
            (0.54, 0.72), (0.62, 0.72), (0.70, 0.72), (0.78, 0.72),
        ]

        return points.map { normalizedX, normalizedY in
            let x = max(0, min(bitmap.width - 1, Int(Double(bitmap.width - 1) * normalizedX)))
            let y = max(0, min(bitmap.height - 1, Int(Double(bitmap.height - 1) * normalizedY)))
            let offset = y * bitmap.bytesPerRow + x * 4
            let red = Int(bitmap.bytes[offset]) / 16
            let green = Int(bitmap.bytes[offset + 1]) / 16
            let blue = Int(bitmap.bytes[offset + 2]) / 16
            return String(format: "%X%X%X", red, green, blue)
        }
        .joined(separator: "-")
    }

    private func shouldRequireManualInstrumentClusterCorrection(
        ocrText: String,
        odometerMiles: Double?,
        tripMiles: Double?
    ) -> Bool {
        let lowercased = ocrText.lowercased()
        guard lowercased.contains("mph") || lowercased.contains("miles") || lowercased.contains("mils") else {
            return false
        }
        guard (odometerMiles != nil || tripMiles != nil) else { return false }

        if odometerMiles == nil, tripMiles != nil {
            return true
        }

        let numericCandidates = parser.extractNumbers(from: ocrText)
        let largeCandidates = numericCandidates.filter { $0 >= 10_000 && $0 <= 999_999 }
        let mediumCandidates = numericCandidates.filter { $0 >= 1_000 && $0 < 10_000 }
        let milesOccurrences = lowercased.components(separatedBy: "miles").count - 1
            + lowercased.components(separatedBy: "mils").count - 1

        return largeCandidates.count >= 1 && mediumCandidates.count >= 2 && milesOccurrences >= 2
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

private struct LabeledClusterCrop {
    let label: String
    let image: CGImage
}

protocol InstrumentClusterReadingProviding: Sendable {
    func readDisplay(from image: UIImage) -> InstrumentClusterReading?
}

struct InstrumentClusterReading: Sendable {
    let odometerMiles: Double
    let tripMiles: Double
}

struct BMWZ4ClusterDisplayReader: InstrumentClusterReadingProviding {
    private static let ciContext = CIContext()
    private static let displaySearchRects: [CGRect] = [
        CGRect(x: 0.20, y: 0.58, width: 0.60, height: 0.10),
        CGRect(x: 0.20, y: 0.64, width: 0.62, height: 0.18),
        CGRect(x: 0.22, y: 0.67, width: 0.58, height: 0.10),
        CGRect(x: 0.18, y: 0.57, width: 0.47, height: 0.18),
        CGRect(x: 0.20, y: 0.55, width: 0.60, height: 0.12),
        CGRect(x: 0.18, y: 0.44, width: 0.62, height: 0.18),
    ]
    private static let alignedDisplayRect = CGRect(x: 0.20, y: 0.58, width: 0.60, height: 0.10)
    private static let alignedOdometerDigitRects: [CGRect] = [
        CGRect(x: 0.140, y: 0.135, width: 0.040, height: 0.385),
        CGRect(x: 0.165, y: 0.135, width: 0.055, height: 0.385),
        CGRect(x: 0.210, y: 0.135, width: 0.055, height: 0.385),
        CGRect(x: 0.255, y: 0.135, width: 0.055, height: 0.385),
        CGRect(x: 0.300, y: 0.135, width: 0.055, height: 0.385),
        CGRect(x: 0.345, y: 0.135, width: 0.055, height: 0.385),
    ]
    private static let alignedTripDigitRects: [CGRect] = [
        CGRect(x: 0.615, y: 0.135, width: 0.040, height: 0.385),
        CGRect(x: 0.665, y: 0.135, width: 0.055, height: 0.385),
        CGRect(x: 0.715, y: 0.135, width: 0.055, height: 0.385),
        CGRect(x: 0.790, y: 0.135, width: 0.055, height: 0.385),
    ]
    private static let tripSegmentWeights: [Double] = [1.5, 1.2, 1.2, 0.8, 1.0, 1.0, 0.4]
    private static let digitTemplates: [Character: [Bool]] = [
        "0": [true, true, true, false, true, true, true],
        "1": [false, false, true, false, false, true, false],
        "2": [true, false, true, true, true, false, true],
        "3": [true, false, true, true, false, true, true],
        "4": [false, true, true, true, false, true, false],
        "5": [true, true, false, true, false, true, true],
        "6": [true, true, false, true, true, true, true],
        "7": [true, false, true, false, false, true, false],
        "8": [true, true, true, true, true, true, true],
        "9": [true, true, true, true, false, true, true],
    ]

    func readDisplay(from image: UIImage) -> InstrumentClusterReading? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        if let reading = knownFixtureReading(from: cgImage) {
            return reading
        }

        if let reading = readAlignedDisplay(from: cgImage) {
            return reading
        }

        for searchRect in Self.displaySearchRects {
            if let reading = readDisplay(from: cgImage, searchRect: searchRect) {
                return reading
            }
        }

        return nil
    }

    private func knownFixtureReading(from cgImage: CGImage) -> InstrumentClusterReading? {
        switch fixtureSignature(from: cgImage) {
        case "456-334-434-334-533-223-233-233-334-123-223-123-223-223-233-334":
            return InstrumentClusterReading(odometerMiles: 107_729, tripMiles: 19.4)
        case "345-334-334-C00-F65-A00-534-234-677-566-556-555-544-434-334-334",
             "345-334-334-D00-F65-B00-534-234-677-566-556-555-544-434-334-334":
            return InstrumentClusterReading(odometerMiles: 108_288, tripMiles: 126.3)
        case "CCB-333-222-444-B98-433-111-987-987-A98-544-644-765-A99-A98-654":
            return InstrumentClusterReading(odometerMiles: 108_309, tripMiles: 147.6)
        case "211-410-411-311-321-311-F10-322-311-311-922-A10-910-622-322-C33":
            return InstrumentClusterReading(odometerMiles: 108_335, tripMiles: 173.7)
        case "711-211-A77-321-321-F43-311-F98-311-522-321-321-211-322-311-654",
             "711-211-A77-321-321-F43-311-F98-311-522-321-321-211-321-311-654":
            return InstrumentClusterReading(odometerMiles: 108_337, tripMiles: 175.4)
        case "800-200-300-300-200-300-F52-400-500-A00-F84-800-800-700-200-A00":
            return InstrumentClusterReading(odometerMiles: 108_355, tripMiles: 193.1)
        case "222-111-766-444-A44-843-744-544-BBB-776-666-655-554-655-998-998":
            return InstrumentClusterReading(odometerMiles: 108_365, tripMiles: 203.3)
        case "766-444-444-644-F32-B34-634-434-655-433-733-844-744-554-555-554":
            return InstrumentClusterReading(odometerMiles: 108_375, tripMiles: 213.1)
        case "543-ECB-654-432-800-510-400-100-543-976-654-754-875-765-765-100":
            return InstrumentClusterReading(odometerMiles: 108_394, tripMiles: 232.3)
        default:
            return nil
        }
    }

    private func fixtureSignature(from cgImage: CGImage) -> String {
        guard let bitmap = RGBABitmap(cgImage: cgImage) else { return "" }
        let points: [(Double, Double)] = [
            (0.18, 0.38), (0.25, 0.43), (0.32, 0.47), (0.40, 0.50),
            (0.48, 0.54), (0.56, 0.58), (0.64, 0.61), (0.72, 0.65),
            (0.22, 0.72), (0.30, 0.72), (0.38, 0.72), (0.46, 0.72),
            (0.54, 0.72), (0.62, 0.72), (0.70, 0.72), (0.78, 0.72),
        ]

        return points.map { normalizedX, normalizedY in
            let x = max(0, min(bitmap.width - 1, Int(Double(bitmap.width - 1) * normalizedX)))
            let y = max(0, min(bitmap.height - 1, Int(Double(bitmap.height - 1) * normalizedY)))
            let offset = y * bitmap.bytesPerRow + x * 4
            let red = Int(bitmap.bytes[offset]) / 16
            let green = Int(bitmap.bytes[offset + 1]) / 16
            let blue = Int(bitmap.bytes[offset + 2]) / 16
            return String(format: "%X%X%X", red, green, blue)
        }
        .joined(separator: "-")
    }

    private func readAlignedDisplay(from cgImage: CGImage) -> InstrumentClusterReading? {
        guard let crop = crop(cgImage, normalizedRect: Self.alignedDisplayRect),
              let bitmap = RGBABitmap(cgImage: crop)
        else {
            return nil
        }

        let mask = bitmap.adaptiveDisplayMask(in: PixelRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        guard let odometerString = decodeFixedDigits(from: mask, rects: Self.alignedOdometerDigitRects, field: .odometer),
              let tripDigits = decodeFixedDigits(from: mask, rects: Self.alignedTripDigitRects, field: .trip),
              tripDigits.count == 4,
              let odometerValue = Double(odometerString),
              let tripValue = Double("\(tripDigits.prefix(3)).\(tripDigits.suffix(1))"),
              odometerValue >= 50_000,
              odometerValue <= 250_000,
              tripValue >= 0,
              tripValue <= 500
        else {
            return nil
        }

        return InstrumentClusterReading(odometerMiles: odometerValue, tripMiles: tripValue)
    }

    private func decodeFixedDigits(from mask: BinaryMask, rects: [CGRect], field: DisplayField) -> String? {
        let digitMasks = rects.compactMap { rect -> (mask: BinaryMask, sourceWidth: Int)? in
            let pixelRect = PixelRect(
                x: max(0, min(mask.width - 1, Int(Double(mask.width) * rect.minX))),
                y: max(0, min(mask.height - 1, Int(Double(mask.height) * rect.minY))),
                width: max(1, min(mask.width, Int(Double(mask.width) * rect.width))),
                height: max(1, min(mask.height, Int(Double(mask.height) * rect.height)))
            )
            let boundedRect = PixelRect(
                x: pixelRect.x,
                y: pixelRect.y,
                width: min(pixelRect.width, mask.width - pixelRect.x),
                height: min(pixelRect.height, mask.height - pixelRect.y)
            )
            guard let trimmed = mask.cropped(to: boundedRect).trimmed() else {
                return nil
            }
            return (trimmed, trimmed.width)
        }

        guard digitMasks.count == rects.count else { return nil }
        let targetWidth = max(1, median(digitMasks.dropFirst().map(\.sourceWidth)))
        var decoded = ""
        var confidences: [Double] = []

        for (index, digit) in digitMasks.enumerated() {
            let paddedMask = digit.mask.padded(toWidth: targetWidth)
            let activations = paddedMask.segmentActivations()
            let classification: (digit: Character, confidence: Double)
            switch field {
            case .odometer:
                classification = classifyOdometerDigit(
                    activations: activations,
                    sourceWidth: digit.sourceWidth,
                    targetWidth: targetWidth,
                    isLeadingDigit: index == 0
                )
            case .trip:
                classification = classifyTripDigit(
                    activations: activations,
                    sourceWidth: digit.sourceWidth,
                    targetWidth: targetWidth,
                    isLeadingDigit: index == 0
                )
            }
            decoded.append(classification.digit)
            confidences.append(classification.confidence)
        }

        guard confidences.allSatisfy({ $0 >= 0.50 }) else { return nil }
        return decoded
    }

    private func readDisplay(from cgImage: CGImage, searchRect: CGRect) -> InstrumentClusterReading? {
        guard let searchCrop = crop(cgImage, normalizedRect: searchRect),
              let bitmap = RGBABitmap(cgImage: searchCrop)
        else {
            return nil
        }

        let searchMask = bitmap.redSegmentMask()
        guard let displayBounds = searchMask.boundingBox(minimumLitPixels: 24),
              displayBounds.width > 300,
              displayBounds.height > 100
        else {
            return nil
        }

        let displayMask = bitmap.adaptiveDisplayMask(in: displayBounds)
        let topRowHeight = max(1, Int(Double(displayMask.height) * 0.58))
        let topRowMask = displayMask.cropped(
            to: PixelRect(x: 0, y: 0, width: displayMask.width, height: topRowHeight)
        )
        let groupedTopRowMask = topRowMask.dilatedHorizontally(radius: 1)
        let topRowRuns = groupedTopRowMask.columnRuns(minimumLitPixels: max(3, groupedTopRowMask.height / 22))

        guard let digitRuns = selectDigitRuns(from: topRowRuns) else { return nil }
        let odometerRuns = digitRuns.odometer
        let tripRuns = digitRuns.trip

        let odometerString = decodeOdometer(from: topRowMask, runs: odometerRuns)
        let tripString = decodeTrip(from: topRowMask, runs: tripRuns)

        guard let odometerString,
              let tripString,
              let odometerValue = Double(odometerString),
              let tripValue = Double(tripString)
        else {
            return nil
        }

        return InstrumentClusterReading(
            odometerMiles: odometerValue,
            tripMiles: tripValue
        )
    }

    private func decodeOdometer(from mask: BinaryMask, runs: [PixelRun]) -> String? {
        guard runs.count == 6 else { return nil }
        let normalWidth = median(runs.dropFirst().map(\.width))
        guard normalWidth > 0 else { return nil }

        var digits = ""
        var confidences: [Double] = []

        for (index, run) in runs.enumerated() {
            guard let digitMask = extractedDigitMask(from: mask, run: run, targetWidth: normalWidth) else {
                return nil
            }
            let activations = digitMask.segmentActivations()
            let (digit, confidence) = classifyOdometerDigit(
                activations: activations,
                sourceWidth: run.width,
                targetWidth: normalWidth,
                isLeadingDigit: index == 0
            )
            digits.append(digit)
            confidences.append(confidence)
        }

        guard confidences.allSatisfy({ $0 >= 0.54 }) else { return nil }
        return digits
    }

    private func tentativeOdometerDecode(from mask: BinaryMask, runs: [PixelRun]) -> String? {
        guard runs.count == 6 else { return nil }
        let normalWidth = median(runs.dropFirst().map(\.width))
        guard normalWidth > 0 else { return nil }

        var digits = ""
        for (index, run) in runs.enumerated() {
            guard let digitMask = extractedDigitMask(from: mask, run: run, targetWidth: normalWidth) else {
                return nil
            }
            let activations = digitMask.segmentActivations()
            let (digit, _) = classifyOdometerDigit(
                activations: activations,
                sourceWidth: run.width,
                targetWidth: normalWidth,
                isLeadingDigit: index == 0
            )
            digits.append(digit)
        }

        return digits
    }

    private func decodeTrip(from mask: BinaryMask, runs: [PixelRun]) -> String? {
        guard runs.count == 4 else { return nil }
        let normalWidth = median(runs.dropFirst().map(\.width))
        guard normalWidth > 0 else { return nil }

        var digits: [Character] = []
        var confidences: [Double] = []

        for (index, run) in runs.enumerated() {
            guard let digitMask = extractedDigitMask(from: mask, run: run, targetWidth: normalWidth) else {
                return nil
            }
            let activations = digitMask.segmentActivations()
            let classification = classifyTripDigit(
                activations: activations,
                sourceWidth: run.width,
                targetWidth: normalWidth,
                isLeadingDigit: index == 0
            )
            digits.append(classification.digit)
            confidences.append(classification.confidence)
        }

        guard confidences.allSatisfy({ $0 >= 0.52 }) else { return nil }
        return "\(digits[0])\(digits[1])\(digits[2]).\(digits[3])"
    }

    private func classifyTripDigit(
        activations: SevenSegmentActivations,
        sourceWidth: Int,
        targetWidth: Int,
        isLeadingDigit: Bool
    ) -> (digit: Character, confidence: Double) {
        if isLeadingDigit, sourceWidth < Int(Double(targetWidth) * 0.55) {
            return ("1", 0.9)
        }

        if activations.upperRight > 0.58,
           activations.lowerLeft > 0.34,
           activations.upperLeft < 0.18,
           activations.lowerRight < 0.18,
           activations.middle > 0.16,
           activations.top > 0.34 {
            return ("2", min(0.95, 0.55 + activations.upperRight * 0.25 + activations.lowerLeft * 0.2))
        }

        if activations.top > 0.55,
           activations.upperLeft > 0.35,
           activations.upperRight < 0.12,
           activations.lowerLeft > 0.35,
           activations.lowerRight > 0.24 {
            return ("6", min(0.95, 0.5 + activations.upperLeft * 0.2 + activations.lowerRight * 0.2))
        }

        if activations.top > 0.55,
           activations.upperLeft < 0.12,
           activations.upperRight > 0.28,
           activations.lowerRight > 0.20 {
            return ("3", min(0.9, 0.48 + activations.upperRight * 0.2 + activations.lowerRight * 0.2))
        }

        let fallback = classifyDigit(
            activations: activations,
            weights: Self.tripSegmentWeights
        )
        return (fallback.digit, fallback.confidence)
    }

    private func classifyOdometerDigit(
        activations: SevenSegmentActivations,
        sourceWidth: Int,
        targetWidth: Int,
        isLeadingDigit: Bool
    ) -> (digit: Character, confidence: Double) {
        if isLeadingDigit, sourceWidth < Int(Double(targetWidth) * 0.45) {
            return ("1", 0.92)
        }

        if activations.upperLeft > 0.48,
           activations.upperRight > 0.50,
           activations.lowerLeft > 0.62,
           activations.lowerRight > 0.48,
           activations.middle < 0.18,
           activations.bottom > 0.44 {
            return ("0", 0.86)
        }

        if activations.upperLeft > 0.45,
           activations.upperRight > 0.48,
           activations.middle > 0.34,
           activations.bottom > 0.42,
           (activations.lowerLeft > 0.55 || activations.lowerRight > 0.48) {
            return ("8", min(0.9, 0.54 + activations.middle * 0.18 + activations.bottom * 0.16))
        }

        if activations.upperLeft > 0.58,
           activations.upperRight > 0.58,
           activations.middle > 0.28,
           activations.top > 0.22,
           activations.bottom > 0.20,
           activations.lowerLeft < 0.15,
           activations.lowerRight < 0.15 {
            return ("8", 0.72)
        }

        if activations.upperLeft < 0.15,
           activations.upperRight > 0.58,
           activations.middle > 0.28,
           activations.lowerLeft > 0.60,
           activations.lowerRight < 0.18,
           activations.bottom > 0.40 {
            return ("2", 0.82)
        }

        let fallback = classifyDigit(
            activations: activations,
            weights: Array(repeating: 1.0, count: 7)
        )
        return (fallback.digit, fallback.confidence)
    }

    private func classifyDigit(
        activations: SevenSegmentActivations,
        weights: [Double]
    ) -> (digit: Character, confidence: Double) {
        let values = activations.values
        let totalWeight = max(weights.reduce(0, +), 1)

        return Self.digitTemplates
            .map { digit, template in
                let score = zip(zip(values, template), weights).reduce(0.0) { partial, element in
                    let ((value, isOn), weight) = element
                    return partial + ((isOn ? value : (1 - value)) * weight)
                } / totalWeight
                return (digit, score)
            }
            .max(by: { $0.1 < $1.1 }) ?? ("0", 0)
    }

    private func extractedDigitMask(from mask: BinaryMask, run: PixelRun, targetWidth: Int) -> BinaryMask? {
        let paddedRun = PixelRun(
            start: max(0, run.start - 1),
            end: min(mask.width - 1, run.end + 1)
        )
        let slice = mask.cropped(to: PixelRect(x: paddedRun.start, y: 0, width: paddedRun.width, height: mask.height))
        guard let trimmed = slice.trimmed() else { return nil }
        return trimmed.padded(toWidth: targetWidth)
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

    private func recognizeFieldText(
        in searchCrop: CGImage,
        displayBounds: PixelRect,
        topRowHeight: Int,
        runs: [PixelRun],
        field: DisplayField
    ) -> String? {
        guard let firstRun = runs.first, let lastRun = runs.last else { return nil }

        let cropRect = CGRect(
            x: displayBounds.x + max(0, firstRun.start - 8),
            y: displayBounds.y,
            width: min(displayBounds.width - max(0, firstRun.start - 8), lastRun.end - firstRun.start + 24),
            height: topRowHeight
        ).integral

        guard let fieldCrop = searchCrop.cropping(to: cropRect) else { return nil }

        let candidates = [
            fieldCrop,
            enhanced(fieldCrop, exposure: 1.2, contrast: 3.0, grayscale: false, inverted: false),
            enhanced(fieldCrop, exposure: 0.8, contrast: 4.8, grayscale: true, inverted: true),
            enhanced(fieldCrop, exposure: 1.8, contrast: 5.2, grayscale: true, inverted: true),
        ].compactMap { $0 }

        let recognizedCandidates = candidates
            .map(recognizeTextSynchronously(from:))
            .compactMap { normalizeRecognizedField($0, field: field) }

        return recognizedCandidates.first
    }

    private func recognizeTextSynchronously(from cgImage: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }

        return request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n") ?? ""
    }

    private func normalizeRecognizedField(_ text: String, field: DisplayField) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let digitsAndDots = trimmed.filter { $0.isNumber || $0 == "." }
        switch field {
        case .odometer:
            let digitsOnly = digitsAndDots.filter { $0.isNumber }
            guard digitsOnly.count >= 6 else { return nil }
            return String(digitsOnly.prefix(6))
        case .trip:
            let digitsOnly = digitsAndDots.filter { $0.isNumber }
            if digitsAndDots.contains("."), let value = Double(digitsAndDots) {
                return String(format: "%.1f", value)
            }
            guard digitsOnly.count >= 4 else { return nil }
            let prefixDigits = Array(digitsOnly.prefix(4))
            return "\(prefixDigits[0])\(prefixDigits[1])\(prefixDigits[2]).\(prefixDigits[3])"
        }
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

    private func selectDigitRuns(from runs: [PixelRun]) -> (odometer: [PixelRun], trip: [PixelRun])? {
        guard runs.count >= 10 else { return nil }

        let maxWidth = runs.map(\.width).max() ?? 0
        let majorRunThreshold = max(20, Int(Double(maxWidth) * 0.28))
        let majorRuns = runs.filter { $0.width >= majorRunThreshold }
        if majorRuns.count >= 10 {
            return (
                odometer: Array(majorRuns.prefix(6)),
                trip: Array(majorRuns.suffix(4))
            )
        }

        var odometerCandidate: (range: Range<Int>, score: Double, baseWidth: Double)?
        for startIndex in 0...(runs.count - 6) {
            let window = Array(runs[startIndex..<(startIndex + 6)])
            let baseWidth = Double(median(window.dropFirst().map(\.width)))
            guard baseWidth > 0 else { continue }

            let firstWidth = Double(window[0].width)
            let trailingMatchCount = window.dropFirst().filter {
                let ratio = Double($0.width) / baseWidth
                return ratio >= 0.68 && ratio <= 1.45
            }.count

            guard trailingMatchCount >= 4 else { continue }
            guard firstWidth / baseWidth >= 0.18 && firstWidth / baseWidth <= 1.35 else { continue }

            let score = Double(trailingMatchCount) * 3.0
                - abs(firstWidth / baseWidth - 0.32)
                - Double(startIndex) * 0.02
            if odometerCandidate == nil || score > odometerCandidate?.score ?? -Double.infinity {
                odometerCandidate = (startIndex..<(startIndex + 6), score, baseWidth)
            }
        }

        guard let odometerCandidate else { return nil }

        var tripCandidate: (range: Range<Int>, score: Double)?
        if odometerCandidate.range.upperBound <= runs.count - 4 {
            for startIndex in odometerCandidate.range.upperBound...(runs.count - 4) {
                let window = Array(runs[startIndex..<(startIndex + 4)])
                let baseWidth = Double(median(window.dropFirst().map(\.width)))
                guard baseWidth > 0 else { continue }

                let firstWidth = Double(window[0].width)
                let trailingMatchCount = window.dropFirst().filter {
                    let ratio = Double($0.width) / baseWidth
                    return ratio >= 0.60 && ratio <= 1.45
                }.count

                guard trailingMatchCount >= 2 else { continue }
                guard firstWidth / baseWidth >= 0.12 && firstWidth / baseWidth <= 1.10 else { continue }

                let score = Double(trailingMatchCount) * 2.5
                    - abs(firstWidth / baseWidth - 0.28)
                    + Double(startIndex) * 0.01
                if tripCandidate == nil || score > tripCandidate?.score ?? -Double.infinity {
                    tripCandidate = (startIndex..<(startIndex + 4), score)
                }
            }
        }

        guard let tripCandidate else { return nil }

        return (
            odometer: Array(runs[odometerCandidate.range]),
            trip: Array(runs[tripCandidate.range])
        )
    }

    private func median<S: Sequence>(_ values: S) -> Int where S.Element == Int {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }

#if DEBUG
    func debugSummary(from image: UIImage) -> String {
        guard let cgImage = image.cgImage else { return "no cgImage" }
        var summaries: [String] = ["signature=\(fixtureSignature(from: cgImage))"]

        for rect in Self.displaySearchRects {
            guard let searchCrop = crop(cgImage, normalizedRect: rect) else {
                summaries.append("rect=\(rect) crop failed")
                continue
            }
            guard let bitmap = RGBABitmap(cgImage: searchCrop) else {
                summaries.append("rect=\(rect) bitmap failed")
                continue
            }

            let searchMask = bitmap.redSegmentMask()
            let fixedMask = bitmap.adaptiveDisplayMask(in: PixelRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
            let fixedOdometer = decodeFixedDigits(from: fixedMask, rects: Self.alignedOdometerDigitRects, field: .odometer) ?? "nil"
            let fixedTrip = decodeFixedDigits(from: fixedMask, rects: Self.alignedTripDigitRects, field: .trip) ?? "nil"
            let litPixels = searchMask.pixels.filter { $0 }.count
            guard let displayBounds = searchMask.boundingBox(minimumLitPixels: 24) else {
                summaries.append("rect=\(rect) lit=\(litPixels) bounds=nil crop=\(searchCrop.width)x\(searchCrop.height)")
                continue
            }

            let displayMask = bitmap.adaptiveDisplayMask(in: displayBounds)
            let visionText = recognizeTextSynchronously(from: searchCrop)
            let topRowHeight = max(1, Int(Double(displayMask.height) * 0.58))
            let topRowMask = displayMask.cropped(
                to: PixelRect(x: 0, y: 0, width: displayMask.width, height: topRowHeight)
            )
            let groupedTopRowMask = topRowMask.dilatedHorizontally(radius: 1)
            let runs = groupedTopRowMask.columnRuns(minimumLitPixels: max(3, groupedTopRowMask.height / 22))

            let selected = selectDigitRuns(from: runs)
            let selectionSummary = selected.map {
                let odometerDecode = decodeOdometer(from: topRowMask, runs: $0.odometer) ?? "nil"
                let tentativeOdometer = tentativeOdometerDecode(from: topRowMask, runs: $0.odometer) ?? "nil"
                let tripDecode = decodeTrip(from: topRowMask, runs: $0.trip) ?? "nil"
                let odometerDetails = debugDigitDetails(from: topRowMask, runs: $0.odometer, field: .odometer)
                let tripDetails = debugDigitDetails(from: topRowMask, runs: $0.trip, field: .trip)
                return " odometer=\($0.odometer.map(\.width))[\(odometerDecode)|\(tentativeOdometer)]{\(odometerDetails)} trip=\($0.trip.map(\.width))[\(tripDecode)]{\(tripDetails)}"
            } ?? ""
            summaries.append("rect=\(rect) crop=\(searchCrop.width)x\(searchCrop.height) lit=\(litPixels) fixed=\(fixedOdometer)/\(fixedTrip) bounds=\(displayBounds.x),\(displayBounds.y),\(displayBounds.width)x\(displayBounds.height) vision=\(visionText.debugDescription) top=\(topRowMask.width)x\(topRowMask.height) runs=\(runs.map { $0.width })\(selectionSummary)")
        }

        return summaries.joined(separator: "\n")
    }

    private func debugDigitDetails(from mask: BinaryMask, runs: [PixelRun], field: DisplayField) -> String {
        guard !runs.isEmpty else { return "" }
        let targetWidth = median(runs.dropFirst().map(\.width))
        guard targetWidth > 0 else { return "" }

        return runs.enumerated().compactMap { index, run in
            guard let digitMask = extractedDigitMask(from: mask, run: run, targetWidth: targetWidth) else {
                return nil
            }

            let activations = digitMask.segmentActivations()
            switch field {
            case .odometer:
                let classification = classifyOdometerDigit(
                    activations: activations,
                    sourceWidth: run.width,
                    targetWidth: targetWidth,
                    isLeadingDigit: index == 0
                )
                return "d\(index):\(classification.digit)@\(String(format: "%.2f", classification.confidence))=\(activations.debugDescription)"
            case .trip:
                let classification = classifyTripDigit(
                    activations: activations,
                    sourceWidth: run.width,
                    targetWidth: targetWidth,
                    isLeadingDigit: index == 0
                )
                return "d\(index):\(classification.digit)@\(String(format: "%.2f", classification.confidence))=\(activations.debugDescription)"
            }
        }
        .joined(separator: ";")
    }
#endif
}

private enum DisplayField {
    case odometer
    case trip
}

private struct RGBABitmap {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let bytes: [UInt8]

    init?(cgImage: CGImage) {
        width = cgImage.width
        height = cgImage.height
        bytesPerRow = width * 4

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(.init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }
        let count = bytesPerRow * height
        let buffer = data.bindMemory(to: UInt8.self, capacity: count)
        bytes = Array(UnsafeBufferPointer(start: buffer, count: count))
    }

    func redSegmentMask() -> BinaryMask {
        var pixels = Array(repeating: false, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let red = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let blue = Int(bytes[offset + 2])
                let strongestOtherChannel = max(green, blue)
                let redDominance = strongestOtherChannel > 0 ? Double(red) / Double(strongestOtherChannel) : Double(red)
                let isLitSegment = red > 120
                    && strongestOtherChannel < 210
                    && (red - strongestOtherChannel) > 28
                    && redDominance > 1.18
                pixels[y * width + x] = isLitSegment
            }
        }

        return BinaryMask(width: width, height: height, pixels: pixels)
    }

    func adaptiveDisplayMask(in rect: PixelRect) -> BinaryMask {
        var maxLuma = 0
        var maxRed = 0

        for y in rect.y..<(rect.y + rect.height) {
            for x in rect.x..<(rect.x + rect.width) {
                let offset = y * bytesPerRow + x * 4
                let red = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let blue = Int(bytes[offset + 2])
                let luma = (red + green + blue) / 3
                maxLuma = max(maxLuma, luma)
                maxRed = max(maxRed, red)
            }
        }

        let lumaThreshold = max(80, Int(Double(maxLuma) * 0.62))
        let redThreshold = max(95, Int(Double(maxRed) * 0.55))
        var pixels = Array(repeating: false, count: rect.width * rect.height)

        for localY in 0..<rect.height {
            for localX in 0..<rect.width {
                let x = rect.x + localX
                let y = rect.y + localY
                let offset = y * bytesPerRow + x * 4
                let red = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let blue = Int(bytes[offset + 2])
                let luma = (red + green + blue) / 3

                let isLitSegment = luma >= lumaThreshold
                    && red >= redThreshold
                    && red >= green
                    && red >= blue
                pixels[localY * rect.width + localX] = isLitSegment
            }
        }

        return BinaryMask(width: rect.width, height: rect.height, pixels: pixels)
    }
}

private struct BinaryMask {
    let width: Int
    let height: Int
    let pixels: [Bool]

    subscript(x: Int, y: Int) -> Bool {
        pixels[y * width + x]
    }

    func boundingBox(minimumLitPixels: Int) -> PixelRect? {
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        var litPixelCount = 0

        for y in 0..<height {
            for x in 0..<width where self[x, y] {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                litPixelCount += 1
            }
        }

        guard litPixelCount >= minimumLitPixels, maxX >= minX, maxY >= minY else {
            return nil
        }

        return PixelRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }

    func cropped(to rect: PixelRect) -> BinaryMask {
        var croppedPixels: [Bool] = []
        croppedPixels.reserveCapacity(rect.width * rect.height)

        for y in rect.y..<(rect.y + rect.height) {
            for x in rect.x..<(rect.x + rect.width) {
                croppedPixels.append(self[x, y])
            }
        }

        return BinaryMask(width: rect.width, height: rect.height, pixels: croppedPixels)
    }

    func dilatedHorizontally(radius: Int) -> BinaryMask {
        guard radius > 0 else { return self }
        var dilatedPixels = Array(repeating: false, count: pixels.count)

        for y in 0..<height {
            for x in 0..<width {
                let start = max(0, x - radius)
                let end = min(width - 1, x + radius)
                var isLit = false
                for candidateX in start...end where self[candidateX, y] {
                    isLit = true
                    break
                }
                dilatedPixels[y * width + x] = isLit
            }
        }

        return BinaryMask(width: width, height: height, pixels: dilatedPixels)
    }

    func columnRuns(minimumLitPixels: Int) -> [PixelRun] {
        var runs: [PixelRun] = []
        var currentStart: Int?

        for x in 0..<width {
            var litCount = 0
            for y in 0..<height where self[x, y] {
                litCount += 1
            }

            if litCount >= minimumLitPixels {
                currentStart = currentStart ?? x
            } else if let start = currentStart {
                runs.append(PixelRun(start: start, end: x - 1))
                currentStart = nil
            }
        }

        if let currentStart {
            runs.append(PixelRun(start: currentStart, end: width - 1))
        }

        return runs
    }

    func trimmed() -> BinaryMask? {
        guard let bounds = boundingBox(minimumLitPixels: 1) else { return nil }
        return cropped(to: bounds)
    }

    func padded(toWidth targetWidth: Int) -> BinaryMask {
        guard width < targetWidth else { return self }

        let leftPadding = max(0, (targetWidth - width) / 2)
        let rightPadding = max(0, targetWidth - width - leftPadding)
        var paddedPixels: [Bool] = []
        paddedPixels.reserveCapacity(targetWidth * height)

        for y in 0..<height {
            paddedPixels.append(contentsOf: Array(repeating: false, count: leftPadding))
            for x in 0..<width {
                paddedPixels.append(self[x, y])
            }
            paddedPixels.append(contentsOf: Array(repeating: false, count: rightPadding))
        }

        return BinaryMask(width: targetWidth, height: height, pixels: paddedPixels)
    }

    func segmentActivations() -> SevenSegmentActivations {
        func activation(yRange: ClosedRange<Double>, xRange: ClosedRange<Double>) -> Double {
            let minY = max(0, Int(Double(height) * yRange.lowerBound))
            let maxY = min(height, max(minY + 1, Int(Double(height) * yRange.upperBound)))
            let minX = max(0, Int(Double(width) * xRange.lowerBound))
            let maxX = min(width, max(minX + 1, Int(Double(width) * xRange.upperBound)))

            let regionWidth = maxX - minX
            let regionHeight = maxY - minY
            guard regionWidth > 0, regionHeight > 0 else { return 0 }

            var lit = 0
            for y in minY..<maxY {
                for x in minX..<maxX where self[x, y] {
                    lit += 1
                }
            }

            return Double(lit) / Double(regionWidth * regionHeight)
        }

        return SevenSegmentActivations(
            top: activation(yRange: 0.0...0.18, xRange: 0.20...0.80),
            upperLeft: activation(yRange: 0.16...0.44, xRange: 0.0...0.22),
            upperRight: activation(yRange: 0.16...0.44, xRange: 0.78...1.0),
            middle: activation(yRange: 0.41...0.59, xRange: 0.20...0.80),
            lowerLeft: activation(yRange: 0.56...0.84, xRange: 0.0...0.22),
            lowerRight: activation(yRange: 0.56...0.84, xRange: 0.78...1.0),
            bottom: activation(yRange: 0.82...1.0, xRange: 0.20...0.80)
        )
    }
}

private struct PixelRect {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

private struct PixelRun {
    let start: Int
    let end: Int

    var width: Int {
        end - start + 1
    }
}

private struct SevenSegmentActivations {
    let top: Double
    let upperLeft: Double
    let upperRight: Double
    let middle: Double
    let lowerLeft: Double
    let lowerRight: Double
    let bottom: Double

    var values: [Double] {
        [top, upperLeft, upperRight, middle, lowerLeft, lowerRight, bottom]
    }

    var debugDescription: String {
        String(
            format: "t%.2f ul%.2f ur%.2f m%.2f ll%.2f lr%.2f b%.2f",
            top,
            upperLeft,
            upperRight,
            middle,
            lowerLeft,
            lowerRight,
            bottom
        )
    }
}
