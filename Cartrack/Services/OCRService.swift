import Foundation
import UIKit
@preconcurrency import Vision

protocol OCRTextRecognizing: Sendable {
    func recognizeText(from image: UIImage?) async -> String
}

struct VisionOCRTextRecognizer: OCRTextRecognizing {
    func recognizeText(from image: UIImage?) async -> String {
        guard let cgImage = image?.cgImage else { return "" }
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
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "")
            }
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
        async let odometerText = recognizer.recognizeText(from: odometerImage)
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
        async let odometerText = recognizer.recognizeText(from: odometerImage)
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
