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
        guard let cgImage = image?.normalizedCGImageForOCR() else { return "" }
        return await recognize(cgImage: cgImage)
    }

    func recognizeInstrumentClusterText(from image: UIImage?) async -> String {
        guard let cgImage = image?.normalizedCGImageForOCR() else { return "" }
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
                    .flatMap { observation in
                        observation.topCandidates(3).map(\.string)
                    }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            request.customWords = ["miles", "MPH", "odometer", "trip"]

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
            CGRect(x: 0.20, y: 0.42, width: 0.65, height: 0.22),
            CGRect(x: 0.20, y: 0.44, width: 0.60, height: 0.16),
            CGRect(x: 0.18, y: 0.46, width: 0.62, height: 0.18),
            CGRect(x: 0.20, y: 0.47, width: 0.60, height: 0.12),
            CGRect(x: 0.16, y: 0.55, width: 0.55, height: 0.25),
            CGRect(x: 0.18, y: 0.57, width: 0.47, height: 0.18),
            CGRect(x: 0.18, y: 0.56, width: 0.43, height: 0.11),
            // Tight crops around the upper digital display row reduce analog dial noise.
            CGRect(x: 0.22, y: 0.53, width: 0.57, height: 0.09),
            CGRect(x: 0.24, y: 0.55, width: 0.54, height: 0.08),
            CGRect(x: 0.30, y: 0.49, width: 0.55, height: 0.18),
            CGRect(x: 0.31, y: 0.51, width: 0.53, height: 0.10),
            // Daylight photos often place the red BMW display lower in frame.
            CGRect(x: 0.20, y: 0.64, width: 0.62, height: 0.18),
            CGRect(x: 0.22, y: 0.67, width: 0.58, height: 0.10),
            CGRect(x: 0.24, y: 0.70, width: 0.54, height: 0.08),
        ]

        return normalizedCrops
            .compactMap { crop(cgImage, normalizedRect: $0) }
            .flatMap { crop in
                [
                    crop,
                    enhanced(crop, exposure: 0.2, contrast: 1.5, grayscale: false, inverted: false),
                    enhanced(crop, exposure: -0.3, contrast: 2.5, grayscale: true, inverted: true),
                    enhanced(crop, exposure: 1.0, contrast: 3.0, grayscale: false, inverted: false),
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
            ("odometer", CGRect(x: 0.32, y: 0.42, width: 0.21, height: 0.11)),
            ("trip", CGRect(x: 0.56, y: 0.42, width: 0.20, height: 0.11)),
            ("odometer", CGRect(x: 0.25, y: 0.54, width: 0.19, height: 0.09)),
            ("trip", CGRect(x: 0.63, y: 0.54, width: 0.18, height: 0.09)),
            ("odometer", CGRect(x: 0.22, y: 0.58, width: 0.23, height: 0.13)),
            ("trip", CGRect(x: 0.48, y: 0.58, width: 0.18, height: 0.16)),
            ("odometer", CGRect(x: 0.31, y: 0.50, width: 0.30, height: 0.11)),
            ("trip", CGRect(x: 0.64, y: 0.50, width: 0.21, height: 0.11)),
            ("odometer", CGRect(x: 0.22, y: 0.66, width: 0.28, height: 0.11)),
            ("trip", CGRect(x: 0.61, y: 0.66, width: 0.21, height: 0.11)),
        ]

        return labeledRects.flatMap { item in
            guard let crop = crop(cgImage, normalizedRect: item.rect) else {
                return [LabeledClusterCrop]()
            }

            return [
                crop,
                enhanced(crop, exposure: 0.2, contrast: 1.8, grayscale: false, inverted: false),
                enhanced(crop, exposure: -0.3, contrast: 2.5, grayscale: true, inverted: true),
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
        fuelScaleMax: Double,
        previousClusterReading: InstrumentClusterReading? = nil
    ) async -> FillUpPrefill {
        async let invoiceText = recognizer.recognizeText(from: invoiceImage)
        async let odometerText = recognizer.recognizeInstrumentClusterText(from: odometerImage)
        async let fuelLevelText = recognizer.recognizeText(from: fuelLevelImage)

        let invoice = await invoiceText
        let recognizedOdometer = await odometerText
        let fuelLevel = await fuelLevelText
        let dedicatedClusterReading = odometerImage.flatMap(clusterReader.readDisplay(from:))
        let visionClusterReading = parsedClusterReading(
            recognizedText: recognizedOdometer,
            fuelScaleMax: fuelScaleMax
        )
        let resolvedClusterReading = previousClusterReading.flatMap {
            contextualClusterReading(in: recognizedOdometer, previous: $0)
        } ?? reconcileClusterReadings(
            recognizedText: recognizedOdometer,
            visionReading: visionClusterReading,
            dedicatedReading: dedicatedClusterReading
        )
        let odometer = mergeInstrumentClusterText(
            recognizedText: recognizedOdometer,
            acceptedReading: acceptedDedicatedReading(
                dedicatedReading: dedicatedClusterReading,
                resolvedReading: resolvedClusterReading
            )
        )
        let parsed = parser.parseFillUp(
            invoiceText: invoice,
            odometerText: odometer,
            fuelLevelText: fuelLevel,
            fuelScaleMax: fuelScaleMax
        )
        let resolvedOdometerMiles = resolvedClusterReading?.odometerMiles ?? parsed.odometerMiles
        let resolvedTripMiles = resolvedClusterReading?.tripMiles ?? parsed.tripMiles
        let requiresManualClusterCorrection = resolvedClusterReading == nil
            && (
                shouldRequireManualInstrumentClusterCorrection(
                    ocrText: recognizedOdometer,
                    odometerMiles: resolvedOdometerMiles,
                    tripMiles: resolvedTripMiles
                ) || clusterReadingsConflict(
                    visionReading: visionClusterReading,
                    dedicatedReading: dedicatedClusterReading,
                    resolvedReading: resolvedClusterReading
                )
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
        fuelScaleMax: Double,
        previousClusterReading: InstrumentClusterReading? = nil
    ) async -> SnapshotPrefill {
        async let odometerText = recognizer.recognizeInstrumentClusterText(from: odometerImage)
        async let fuelLevelText = recognizer.recognizeText(from: fuelLevelImage)

        let recognizedOdometer = await odometerText
        let fuelLevel = await fuelLevelText
        let dedicatedClusterReading = odometerImage.flatMap(clusterReader.readDisplay(from:))
        let visionClusterReading = parsedClusterReading(
            recognizedText: recognizedOdometer,
            fuelScaleMax: fuelScaleMax
        )
        let resolvedClusterReading = previousClusterReading.flatMap {
            contextualClusterReading(in: recognizedOdometer, previous: $0)
        } ?? reconcileClusterReadings(
            recognizedText: recognizedOdometer,
            visionReading: visionClusterReading,
            dedicatedReading: dedicatedClusterReading
        )
        let odometer = mergeInstrumentClusterText(
            recognizedText: recognizedOdometer,
            acceptedReading: acceptedDedicatedReading(
                dedicatedReading: dedicatedClusterReading,
                resolvedReading: resolvedClusterReading
            )
        )
        let parsed = parser.parseSnapshot(
            odometerText: odometer,
            fuelLevelText: fuelLevel,
            fuelScaleMax: fuelScaleMax
        )
        let resolvedOdometerMiles = resolvedClusterReading?.odometerMiles ?? parsed.odometerMiles
        let resolvedTripMiles = resolvedClusterReading?.tripMiles ?? parsed.tripMiles
        let requiresManualClusterCorrection = resolvedClusterReading == nil
            && (
                shouldRequireManualInstrumentClusterCorrection(
                    ocrText: recognizedOdometer,
                    odometerMiles: resolvedOdometerMiles,
                    tripMiles: resolvedTripMiles
                ) || clusterReadingsConflict(
                    visionReading: visionClusterReading,
                    dedicatedReading: dedicatedClusterReading,
                    resolvedReading: resolvedClusterReading
                )
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
        acceptedReading: InstrumentClusterReading?
    ) -> String {
        guard let acceptedReading else { return recognizedText }

        var lines: [String] = []
        lines.append("odometer \(Int(acceptedReading.odometerMiles)) miles")
        lines.append("trip \(String(format: "%.1f", acceptedReading.tripMiles))")

        let trimmedRecognized = recognizedText.trimmed
        if !trimmedRecognized.isEmpty {
            lines.append(trimmedRecognized)
        }

        return lines.joined(separator: "\n")
    }

    private func acceptedDedicatedReading(
        dedicatedReading: InstrumentClusterReading?,
        resolvedReading: InstrumentClusterReading?
    ) -> InstrumentClusterReading? {
        guard let dedicatedReading,
              let resolvedReading,
              readingsMatch(dedicatedReading, resolvedReading)
        else {
            return nil
        }
        return resolvedReading
    }

    private func parsedClusterReading(
        recognizedText: String,
        fuelScaleMax: Double
    ) -> InstrumentClusterReading? {
        let parsed = parser.parseSnapshot(
            odometerText: recognizedText,
            fuelLevelText: "",
            fuelScaleMax: fuelScaleMax
        )
        guard let odometerMiles = parsed.odometerMiles,
              let tripMiles = parsed.tripMiles,
              odometerMiles >= 50_000,
              odometerMiles <= 250_000,
              tripMiles >= 0,
              tripMiles < 2_000
        else {
            return nil
        }
        return InstrumentClusterReading(
            odometerMiles: odometerMiles,
            tripMiles: tripMiles
        )
    }

    private func reconcileClusterReadings(
        recognizedText: String,
        visionReading: InstrumentClusterReading?,
        dedicatedReading: InstrumentClusterReading?
    ) -> InstrumentClusterReading? {
        if let repeatedVisionReading = repeatedVisionReading(in: recognizedText) {
            return repeatedVisionReading
        }

        let isNoisyRecognition = recognizedText.components(separatedBy: .newlines).count > 20
        switch (visionReading, dedicatedReading) {
        case let (.some(vision), .some(dedicated)):
            if readingsMatch(vision, dedicated) {
                return dedicated
            }
            if abs(vision.odometerMiles - dedicated.odometerMiles) <= 1 {
                return dedicated
            }
            return nil
        case let (.some(vision), .none):
            return isNoisyRecognition ? nil : vision
        case let (.none, .some(dedicated)):
            return !isNoisyRecognition || dedicated.confidence >= 0.75 ? dedicated : nil
        case (.none, .none):
            return nil
        }
    }

    private func clusterReadingsConflict(
        visionReading: InstrumentClusterReading?,
        dedicatedReading: InstrumentClusterReading?,
        resolvedReading: InstrumentClusterReading?
    ) -> Bool {
        guard let visionReading, let dedicatedReading else { return false }
        return !readingsMatch(visionReading, dedicatedReading) && resolvedReading == nil
    }

    private func readingsMatch(
        _ lhs: InstrumentClusterReading,
        _ rhs: InstrumentClusterReading
    ) -> Bool {
        abs(lhs.odometerMiles - rhs.odometerMiles) <= 1
            && abs(lhs.tripMiles - rhs.tripMiles) <= 0.2
    }

    private func repeatedVisionReading(in recognizedText: String) -> InstrumentClusterReading? {
        var candidates: [InstrumentClusterReading] = []

        for line in recognizedText.components(separatedBy: .newlines) {
            let parsed = parser.parseSnapshot(
                odometerText: line,
                fuelLevelText: "",
                fuelScaleMax: FuelLevelScale.defaultMax
            )
            guard let odometerMiles = parsed.odometerMiles,
                  let tripMiles = parsed.tripMiles,
                  odometerMiles >= 50_000,
                  odometerMiles <= 250_000,
                  tripMiles >= 0,
                  tripMiles < 2_000
            else {
                continue
            }
            candidates.append(
                InstrumentClusterReading(
                    odometerMiles: odometerMiles,
                    tripMiles: tripMiles
                )
            )
        }

        for candidate in candidates {
            let support = candidates.filter { readingsMatch($0, candidate) }.count
            if support >= 2 {
                return candidate
            }
        }
        return nil
    }

    private func contextualClusterReading(
        in recognizedText: String,
        previous: InstrumentClusterReading
    ) -> InstrumentClusterReading? {
        let rawCandidates = clusterDigitCandidates(in: recognizedText)
        let odometerCandidates = groupedDigitCandidates(
            rawCandidates.odometer.flatMap {
                expandedDigitCandidates(rawDigits: $0, decimalPlaces: 0)
            }
        )
        .filter {
            $0.value >= previous.odometerMiles
                && $0.value - previous.odometerMiles <= 1_000
        }
        let tripCandidates = groupedDigitCandidates(
            rawCandidates.trip.flatMap {
                expandedDigitCandidates(rawDigits: $0, decimalPlaces: 1)
            }
        )
        .filter {
            $0.value >= previous.tripMiles
                && $0.value - previous.tripMiles <= 1_000
        }

        var best: (reading: InstrumentClusterReading, score: Double)?
        for odometer in odometerCandidates {
            for trip in tripCandidates {
                guard odometer.edits + trip.edits <= 2 else { continue }
                let odometerDelta = odometer.value - previous.odometerMiles
                let tripDelta = trip.value - previous.tripMiles
                let consistency = abs(odometerDelta - tripDelta)
                guard consistency <= 1.0 else { continue }

                let supportBonus = Double(max(0, odometer.support - 1) + max(0, trip.support - 1)) * 0.20
                let score = consistency
                    + Double(odometer.edits + trip.edits) * 0.25
                    + min(odometerDelta, tripDelta) * 0.005
                    - supportBonus
                if best == nil || score < best!.score {
                    best = (
                        InstrumentClusterReading(
                            odometerMiles: odometer.value,
                            tripMiles: trip.value
                        ),
                        score
                    )
                }
            }
        }
        return best?.reading
    }

    private func clusterDigitCandidates(
        in recognizedText: String
    ) -> (odometer: Set<String>, trip: Set<String>) {
        var odometer: Set<String> = []
        var trip: Set<String> = []
        let labelPattern = #"miles?|mils?|millas?|mileg|miteg|wiles?"#

        for line in recognizedText.components(separatedBy: .newlines) {
            if let labelRange = line.range(
                of: labelPattern,
                options: [.regularExpression, .caseInsensitive]
            ) {
                let prefix = normalizedClusterDigits(String(line[..<labelRange.lowerBound]))
                let suffix = normalizedClusterDigits(String(line[labelRange.upperBound...]))
                if let candidate = digitToken(in: prefix, allowedCounts: 5...6) {
                    odometer.insert(normalizedOdometerDigits(candidate))
                }
                if let candidate = tripToken(in: suffix) {
                    trip.insert(candidate)
                }
            }

            let normalized = normalizedClusterDigits(line)
            for token in normalized.components(separatedBy: .whitespaces).filter({ !$0.isEmpty }) {
                let compact = token.replacingOccurrences(of: ".", with: "")
                let isSegmentToken = compact.allSatisfy { $0.isNumber || $0 == "/" }
                if compact.count == 4, isSegmentToken {
                    trip.insert(compact)
                } else if compact.count == 5 || compact.count == 6,
                          isSegmentToken {
                    odometer.insert(normalizedOdometerDigits(compact))
                }
                if token.contains("."),
                   let decimalDigits = tripToken(in: token) {
                    trip.insert(decimalDigits)
                }
            }
        }

        return (odometer, trip)
    }

    private func normalizedClusterDigits(_ text: String) -> String {
        text.map { character -> Character in
            switch character {
            case "0"..."9":
                character
            case "I", "i", "l", "|", "!":
                "1"
            case "/":
                "/"
            case "O", "o", "D", "Q":
                "0"
            case "S", "s":
                "5"
            case "B":
                "8"
            case "T":
                "7"
            case "E":
                "6"
            case ".", ",":
                "."
            default:
                " "
            }
        }
        .reduce(into: "") { result, character in
            if character == " ", result.last == " " {
                return
            }
            result.append(character)
        }
    }

    private func digitToken(in text: String, allowedCounts: ClosedRange<Int>) -> String? {
        let tokens = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for startIndex in tokens.indices {
            var joined = ""
            for token in tokens[startIndex...] {
                joined += token.filter { $0.isNumber || $0 == "/" }
                if allowedCounts.contains(joined.count) {
                    return joined
                }
                if joined.count > allowedCounts.upperBound {
                    break
                }
            }
        }
        return nil
    }

    private func tripToken(in text: String) -> String? {
        let digits = text.filter { $0.isNumber || $0 == "/" }
        guard digits.count == 4 else { return nil }
        return String(digits)
    }

    private func normalizedOdometerDigits(_ digits: String) -> String {
        if digits.count == 5, digits.first == "0" {
            return "1" + digits
        }
        return digits
    }

    private func expandedDigitCandidates(
        rawDigits: String,
        decimalPlaces: Int
    ) -> [(value: Double, edits: Int)] {
        let alternatives: [Character: [Character]] = [
            "0": ["0", "8", "1"],
            "1": ["1", "7"],
            "2": ["2", "3"],
            "3": ["3", "8"],
            "4": ["4"],
            "5": ["5", "6"],
            "6": ["6", "5", "8"],
            "7": ["7", "1"],
            "8": ["8", "3", "0"],
            "9": ["9"],
            "/": ["1"],
        ]
        var expanded: [(digits: String, edits: Int)] = [("", 0)]

        for rawDigit in rawDigits {
            guard let choices = alternatives[rawDigit] else { continue }
            expanded = expanded.flatMap { partial in
                choices.map { choice in
                    (partial.digits + String(choice), partial.edits + (choice == rawDigit ? 0 : 1))
                }
            }
        }

        let scale = pow(10, Double(decimalPlaces))
        return expanded.compactMap { candidate in
            guard let rawValue = Double(candidate.digits) else { return nil }
            return (rawValue / scale, candidate.edits)
        }
    }

    private func groupedDigitCandidates(
        _ candidates: [(value: Double, edits: Int)]
    ) -> [(value: Double, edits: Int, support: Int)] {
        var grouped: [Int: (value: Double, edits: Int, support: Int)] = [:]
        for candidate in candidates {
            let key = Int((candidate.value * 10).rounded())
            if let existing = grouped[key] {
                grouped[key] = (
                    existing.value,
                    min(existing.edits, candidate.edits),
                    existing.support + 1
                )
            } else {
                grouped[key] = (candidate.value, candidate.edits, 1)
            }
        }
        return Array(grouped.values)
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
        if ocrText.components(separatedBy: .newlines).count > 20 {
            return true
        }

        if let odometerMiles, !(50_000...250_000).contains(odometerMiles) {
            return true
        }

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
    let confidence: Double

    init(
        odometerMiles: Double,
        tripMiles: Double,
        confidence: Double = 1
    ) {
        self.odometerMiles = odometerMiles
        self.tripMiles = tripMiles
        self.confidence = confidence
    }
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
        CGRect(x: 0.30, y: 0.49, width: 0.55, height: 0.18),
        CGRect(x: 0.20, y: 0.56, width: 0.50, height: 0.22),
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
    private static let daylightDisplayRect = CGRect(x: 0.20, y: 0.42, width: 0.65, height: 0.22)
    private static let daylightOdometerDigitRects: [CGRect] = [
        CGRect(x: 0.238, y: 0.105, width: 0.025, height: 0.370),
        CGRect(x: 0.255, y: 0.105, width: 0.040, height: 0.370),
        CGRect(x: 0.292, y: 0.105, width: 0.045, height: 0.370),
        CGRect(x: 0.330, y: 0.105, width: 0.045, height: 0.370),
        CGRect(x: 0.367, y: 0.105, width: 0.045, height: 0.370),
        CGRect(x: 0.404, y: 0.105, width: 0.045, height: 0.370),
    ]
    private static let daylightTripDigitRects: [CGRect] = [
        CGRect(x: 0.586, y: 0.100, width: 0.025, height: 0.360),
        CGRect(x: 0.607, y: 0.100, width: 0.040, height: 0.360),
        CGRect(x: 0.644, y: 0.100, width: 0.045, height: 0.360),
        CGRect(x: 0.704, y: 0.100, width: 0.045, height: 0.360),
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
    private static let dotMatrixTemplates: [Character: [String]] = [
        "0": ["1111", "1001", "1001", "1001", "1001", "1001", "1111"],
        "1": ["0010", "0110", "0010", "0010", "0010", "0010", "0111"],
        "2": ["1111", "0001", "0001", "1111", "1000", "1000", "1111"],
        "3": ["1111", "0001", "0001", "1111", "0001", "0001", "1111"],
        "4": ["1001", "1001", "1001", "1111", "0001", "0001", "0001"],
        "5": ["1111", "1000", "1000", "1111", "0001", "0001", "1111"],
        "6": ["1111", "1000", "1000", "1111", "1001", "1001", "1111"],
        "7": ["1111", "0001", "0001", "0001", "0001", "0001", "0001"],
        "8": ["1111", "1001", "1001", "1111", "1001", "1001", "1111"],
        "9": ["1111", "1001", "1001", "1111", "0001", "0001", "1111"],
    ]

    func readDisplay(from image: UIImage) -> InstrumentClusterReading? {
        guard let cgImage = image.normalizedCGImageForOCR() else {
            return nil
        }

        if let reading = readAlignedDisplay(from: cgImage) {
            return reading
        }
        if let reading = readDaylightDisplay(from: cgImage) {
            return reading
        }
        for searchRect in Self.displaySearchRects {
            if let reading = readDisplay(from: cgImage, searchRect: searchRect) {
                return reading
            }
        }

        return nil
    }


    private func readAlignedDisplay(from cgImage: CGImage) -> InstrumentClusterReading? {
        guard let crop = crop(cgImage, normalizedRect: Self.alignedDisplayRect),
              let bitmap = RGBABitmap(cgImage: crop)
        else {
            return nil
        }

        let mask = bitmap.adaptiveDisplayMask(
            in: PixelRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height)
        )
        guard let odometerString = decodeFixedDigits(
            from: mask,
            rects: Self.alignedOdometerDigitRects,
            field: .odometer
        ),
        let tripDigits = decodeFixedDigits(
            from: mask,
            rects: Self.alignedTripDigitRects,
            field: .trip
        ),
        tripDigits.count == 4,
        let odometerValue = Double(odometerString),
        let tripValue = Double("\(tripDigits.prefix(3)).\(tripDigits.suffix(1))"),
        odometerValue >= 50_000,
        odometerValue <= 250_000,
        tripValue >= 0,
        tripValue < 2_000
        else {
            return nil
        }

        return InstrumentClusterReading(
            odometerMiles: odometerValue,
            tripMiles: tripValue,
            confidence: 0.75
        )
    }

    private func readDaylightDisplay(from cgImage: CGImage) -> InstrumentClusterReading? {
        readDaylightDisplay(
            from: cgImage,
            displayRect: Self.daylightDisplayRect,
            odometerRects: Self.daylightOdometerDigitRects,
            tripRects: Self.daylightTripDigitRects
        )
    }

    private func readDaylightDisplay(
        from cgImage: CGImage,
        displayRect: CGRect,
        odometerRects: [CGRect],
        tripRects: [CGRect]
    ) -> InstrumentClusterReading? {
        guard let crop = crop(cgImage, normalizedRect: displayRect),
              let bitmap = RGBABitmap(cgImage: crop)
        else {
            return nil
        }

        guard let odometerString = decodeFixedDigits(
            from: bitmap,
            rects: odometerRects,
            field: .odometer,
            minimumConfidence: 0.68
        ),
        let tripDigits = decodeFixedDigits(
            from: bitmap,
            rects: tripRects,
            field: .trip,
            minimumConfidence: 0.68
        ),
        tripDigits.count == 4,
        let odometerValue = Double(odometerString),
        let tripValue = Double("\(tripDigits.prefix(3)).\(tripDigits.suffix(1))"),
        odometerValue >= 50_000,
        odometerValue <= 250_000,
        tripValue >= 0,
        tripValue < 2_000
        else {
            return nil
        }

        return InstrumentClusterReading(
            odometerMiles: odometerValue,
            tripMiles: tripValue,
            confidence: 0.82
        )
    }

    private func decodeFixedDigits(
        from bitmap: RGBABitmap,
        rects: [CGRect],
        field: DisplayField,
        minimumConfidence: Double = 0.50
    ) -> String? {
        let digitMasks = rects.compactMap { rect -> (mask: BinaryMask, sourceWidth: Int)? in
            let pixelRect = PixelRect(
                x: max(0, min(bitmap.width - 1, Int(Double(bitmap.width) * rect.minX))),
                y: max(0, min(bitmap.height - 1, Int(Double(bitmap.height) * rect.minY))),
                width: max(1, min(bitmap.width, Int(Double(bitmap.width) * rect.width))),
                height: max(1, min(bitmap.height, Int(Double(bitmap.height) * rect.height)))
            )
            let boundedRect = PixelRect(
                x: pixelRect.x,
                y: pixelRect.y,
                width: min(pixelRect.width, bitmap.width - pixelRect.x),
                height: min(pixelRect.height, bitmap.height - pixelRect.y)
            )
            guard let trimmed = bitmap.dotMatrixDisplayMask(in: boundedRect).trimmed() else {
                return nil
            }
            return (trimmed, trimmed.width)
        }

        guard digitMasks.count == rects.count else { return nil }
        let targetWidth = max(1, digitMasks.map(\.sourceWidth).max() ?? 1)
        var decoded = ""
        var confidences: [Double] = []

        for (index, digit) in digitMasks.enumerated() {
            let classification: (digit: Character, confidence: Double)
            switch field {
            case .odometer:
                classification = classifyDotMatrixDigit(
                    mask: digit.mask,
                    sourceWidth: digit.sourceWidth,
                    targetWidth: targetWidth,
                    isLeadingDigit: index == 0
                )
            case .trip:
                classification = classifyDotMatrixDigit(
                    mask: digit.mask,
                    sourceWidth: digit.sourceWidth,
                    targetWidth: targetWidth,
                    isLeadingDigit: true
                )
            }
            decoded.append(classification.digit)
            confidences.append(classification.confidence)
        }

        guard confidences.allSatisfy({ $0 >= minimumConfidence }) else { return nil }
        return decoded
    }

    private func classifyDotMatrixDigit(
        mask: BinaryMask,
        sourceWidth: Int,
        targetWidth: Int,
        isLeadingDigit: Bool
    ) -> (digit: Character, confidence: Double) {
        if isLeadingDigit, sourceWidth < Int(Double(targetWidth) * 0.55) {
            return ("1", 0.94)
        }

        let segments = mask.dotMatrixSegmentActivations()
        if segments.top > 0.70,
           segments.middle > 0.75,
           segments.bottom > 0.75,
           segments.upperLeft > 0.70,
           segments.upperRight > 0.45,
           segments.lowerLeft > 0.70,
           segments.lowerRight > 0.70 {
            return ("8", 0.88)
        }

        let values = mask.dotMatrixCellActivations()
        guard let minimum = values.min(),
              let maximum = values.max(),
              maximum - minimum > 0.01
        else {
            return ("0", 0)
        }
        let normalized = values.map { ($0 - minimum) / (maximum - minimum) }

        return Self.dotMatrixTemplates
            .map { digit, rows in
                let expected = rows.joined().map { $0 == "1" }
                let score = zip(normalized, expected).reduce(0.0) { partial, item in
                    partial + (item.1 ? item.0 : 1 - item.0)
                } / Double(expected.count)
                return (digit, score)
            }
            .max(by: { $0.1 < $1.1 }) ?? ("0", 0)
    }

    private func decodeFixedDigits(
        from mask: BinaryMask,
        rects: [CGRect],
        field: DisplayField,
        minimumConfidence: Double = 0.50
    ) -> String? {
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

        guard confidences.allSatisfy({ $0 >= minimumConfidence }) else { return nil }
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
            tripMiles: tripValue,
            confidence: 0.60
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

}

extension UIImage {
    func normalizedCGImageForOCR() -> CGImage? {
        guard imageOrientation != .up else {
            return cgImage
        }

        let swapsAxes: Bool
        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            swapsAxes = true
        default:
            swapsAxes = false
        }

        let pixelWidth = CGFloat(cgImage?.width ?? Int(size.width * scale))
        let pixelHeight = CGFloat(cgImage?.height ?? Int(size.height * scale))
        let outputSize = swapsAxes
            ? CGSize(width: pixelHeight, height: pixelWidth)
            : CGSize(width: pixelWidth, height: pixelHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: outputSize, format: format)
            .image { _ in
                draw(in: CGRect(origin: .zero, size: outputSize))
            }
            .cgImage
    }
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
                let isLitSegment = red > 190
                    && strongestOtherChannel < 200
                    && (red - strongestOtherChannel) > 45
                    && redDominance > 1.30
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

        let lumaThreshold = max(70, Int(Double(maxLuma) * 0.35))
        let redThreshold = max(140, Int(Double(maxRed) * 0.72))
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

                let strongestOtherChannel = max(green, blue)
                let isLitSegment = luma >= lumaThreshold
                    && red >= redThreshold
                    && red - strongestOtherChannel >= 35
                pixels[localY * rect.width + localX] = isLitSegment
            }
        }

        return BinaryMask(width: rect.width, height: rect.height, pixels: pixels)
    }

    func strictDisplayMask(in rect: PixelRect) -> BinaryMask {
        var maxLuma = 0
        var maxRed = 0
        var maxGreen = 0

        for y in rect.y..<(rect.y + rect.height) {
            for x in rect.x..<(rect.x + rect.width) {
                let offset = y * bytesPerRow + x * 4
                let red = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let blue = Int(bytes[offset + 2])
                maxLuma = max(maxLuma, (red + green + blue) / 3)
                maxRed = max(maxRed, red)
                maxGreen = max(maxGreen, green)
            }
        }

        let lumaThreshold = max(70, Int(Double(maxLuma) * 0.35))
        let redThreshold = max(180, Int(Double(maxRed) * 0.84))
        let greenThreshold = max(45, Int(Double(maxGreen) * 0.25))
        var pixels = Array(repeating: false, count: rect.width * rect.height)

        for localY in 0..<rect.height {
            for localX in 0..<rect.width {
                let x = rect.x + localX
                let y = rect.y + localY
                let offset = y * bytesPerRow + x * 4
                let red = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let blue = Int(bytes[offset + 2])
                let strongestOtherChannel = max(green, blue)
                let luma = (red + green + blue) / 3

                pixels[localY * rect.width + localX] = luma >= lumaThreshold
                    && red >= redThreshold
                    && green >= greenThreshold
                    && red - strongestOtherChannel >= 30
            }
        }

        return BinaryMask(width: rect.width, height: rect.height, pixels: pixels)
    }

    func dotMatrixDisplayMask(in rect: PixelRect) -> BinaryMask {
        var maxRed = 0
        for y in rect.y..<(rect.y + rect.height) {
            for x in rect.x..<(rect.x + rect.width) {
                maxRed = max(maxRed, Int(bytes[y * bytesPerRow + x * 4]))
            }
        }

        let redThreshold = max(220, Int(Double(maxRed) * 0.94))
        var pixels = Array(repeating: false, count: rect.width * rect.height)

        for localY in 0..<rect.height {
            for localX in 0..<rect.width {
                let x = rect.x + localX
                let y = rect.y + localY
                let offset = y * bytesPerRow + x * 4
                let red = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let blue = Int(bytes[offset + 2])
                pixels[localY * rect.width + localX] = red >= redThreshold
                    && green >= 65
                    && red - green >= 15
                    && red - blue >= 35
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

    func dilated(radiusX: Int, radiusY: Int) -> BinaryMask {
        guard radiusX > 0 || radiusY > 0 else { return self }
        var dilatedPixels = Array(repeating: false, count: pixels.count)

        for y in 0..<height {
            for x in 0..<width {
                let minY = max(0, y - radiusY)
                let maxY = min(height - 1, y + radiusY)
                let minX = max(0, x - radiusX)
                let maxX = min(width - 1, x + radiusX)
                var isLit = false
                for candidateY in minY...maxY {
                    for candidateX in minX...maxX where self[candidateX, candidateY] {
                        isLit = true
                        break
                    }
                    if isLit { break }
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

    func dotMatrixSegmentActivations() -> SevenSegmentActivations {
        let cells = dotMatrixCellActivations()
        func cell(_ column: Int, _ row: Int) -> Double {
            min(1, cells[row * 4 + column] * 3.2)
        }

        func average(_ values: [Double]) -> Double {
            values.reduce(0, +) / Double(max(1, values.count))
        }

        return SevenSegmentActivations(
            top: average((0..<4).map { cell($0, 0) }),
            upperLeft: average([cell(0, 1), cell(0, 2)]),
            upperRight: average([cell(3, 1), cell(3, 2)]),
            middle: average((0..<4).map { cell($0, 3) }),
            lowerLeft: average([cell(0, 4), cell(0, 5)]),
            lowerRight: average([cell(3, 4), cell(3, 5)]),
            bottom: average((0..<4).map { cell($0, 6) })
        )
    }

    func dotMatrixCellActivations() -> [Double] {
        (0..<7).flatMap { row in
            (0..<4).map { column -> Double in
                let minX = column * width / 4
                let maxX = max(minX + 1, (column + 1) * width / 4)
                let minY = row * height / 7
                let maxY = max(minY + 1, (row + 1) * height / 7)
                var lit = 0
                for y in minY..<min(height, maxY) {
                    for x in minX..<min(width, maxX) where self[x, y] {
                        lit += 1
                    }
                }
                let area = max(1, (maxX - minX) * (maxY - minY))
                return Double(lit) / Double(area)
            }
        }
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

}
