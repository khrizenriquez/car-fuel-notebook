import Foundation

struct OCRTextParser {
    func parseFillUp(invoiceText: String, odometerText: String, fuelLevelText: String, fuelScaleMax: Double) -> FillUpTextParseResult {
        FillUpTextParseResult(
            gallons: parseGallons(from: invoiceText),
            pricePerGallon: parsePricePerGallon(from: invoiceText),
            totalCost: parseTotalCost(from: invoiceText),
            odometerMiles: parseLargestMileage(from: odometerText),
            tripMiles: parseTripMileage(from: odometerText),
            fuelLevelRemaining: parseFuelLevel(from: fuelLevelText, fuelScaleMax: fuelScaleMax)
        )
    }

    func parseSnapshot(odometerText: String, fuelLevelText: String, fuelScaleMax: Double) -> SnapshotTextParseResult {
        SnapshotTextParseResult(
            odometerMiles: parseLargestMileage(from: odometerText),
            tripMiles: parseTripMileage(from: odometerText),
            fuelLevelRemaining: parseFuelLevel(from: fuelLevelText, fuelScaleMax: fuelScaleMax)
        )
    }

    func parseGallons(from text: String) -> Double? {
        parseDecimal(afterKeywords: ["galones", "gallons", "cantidad", "cant. gal", "cant gal", "cant", "despachado", "volumen"], in: text, min: 1, max: 30)
            ?? parseDecimal(beforeKeywords: ["galones", "gallons", "gals", "gal"], in: text, min: 1, max: 30)
            ?? bestDecimalCandidate(in: text, min: 1, max: 30)
    }

    func parsePricePerGallon(from text: String) -> Double? {
        parseDecimal(afterKeywords: ["precio por galon", "precio unitario", "precio x galon", "precio gal", "p/gal", "p.gal", "p.u.", "p/u", "precio"], in: text, min: 10, max: 80)
            ?? bestDecimalCandidate(in: text, min: 10, max: 80)
    }

    func parseTotalCost(from text: String) -> Double? {
        parseDecimal(afterKeywords: ["total pagado", "total a pagar", "monto total", "importe", "total"], in: text, min: 20, max: 5_000)
            ?? bestDecimalCandidate(in: text, min: 20, max: 5_000)
    }

    func parseLargestMileage(from text: String) -> Double? {
        parseDecimal(afterKeywords: ["odometro", "odometer", "odo", "millas", "mileage"], in: text, min: 1_000, max: 999_999)
            ??
        extractNumbers(from: text)
            .filter { $0 > 1_000 && $0 < 999_999 }
            .sorted(by: >)
            .first
    }

    func parseTripMileage(from text: String) -> Double? {
        parseDecimal(afterKeywords: ["trip meter", "tripmeter", "trip"], in: text, min: 0, max: 2_000)
            ??
        extractNumbers(from: text)
            .filter { $0 >= 0 && $0 < 2_000 }
            .sorted(by: >)
            .first
    }

    func parseFuelLevel(from text: String, fuelScaleMax: Double) -> Double? {
        guard let value = parseFraction(afterKeywords: ["espacios restantes", "spaces remaining", "quedan", "restante", "nivel", "fuel level"], in: text, min: 0, max: fuelScaleMax)
            ?? parseDecimal(afterKeywords: ["espacios restantes", "spaces remaining", "quedan", "restante", "nivel", "fuel level"], in: text, min: 0, max: fuelScaleMax)
            ?? parseDecimal(beforeKeywords: ["espacios", "spaces", "barras"], in: text, min: 0, max: fuelScaleMax)
            ?? bestDecimalCandidate(in: text, min: 0, max: fuelScaleMax)
        else { return nil }
        return FuelLevelScale.normalize(value, maxValue: fuelScaleMax)
    }

    func extractNumbers(from text: String) -> [Double] {
        let pattern = #"\d+(?:(?:[.,]\d+)|(?:\s+\d{3}))*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            normalizeNumber(nsText.substring(with: match.range))
        }
    }

    private func parseDecimal(afterKeywords keywords: [String], in text: String, min: Double, max: Double) -> Double? {
        let lowercased = text.lowercased()
        let lines = lowercased.components(separatedBy: .newlines)

        for keyword in keywords {
            for line in lines where line.contains(keyword.lowercased()) {
                if let value = extractNumbers(from: line).first(where: { $0 >= min && $0 <= max }) {
                    return value
                }
            }
        }

        for keyword in keywords {
            guard let range = lowercased.range(of: keyword.lowercased()) else { continue }
            let suffix = String(lowercased[range.lowerBound...].prefix(60))
            if let match = extractNumbers(from: suffix).first(where: { $0 >= min && $0 <= max }) {
                return match
            }
        }
        return nil
    }

    private func parseFraction(afterKeywords keywords: [String], in text: String, min: Double, max: Double) -> Double? {
        let lowercased = text.lowercased()
        let lines = lowercased.components(separatedBy: .newlines)

        for keyword in keywords {
            for line in lines where line.contains(keyword.lowercased()) {
                if let value = extractFractions(from: line).first(where: { $0 >= min && $0 <= max }) {
                    return value
                }
            }
        }

        for keyword in keywords {
            guard let range = lowercased.range(of: keyword.lowercased()) else { continue }
            let suffix = String(lowercased[range.lowerBound...].prefix(60))
            if let value = extractFractions(from: suffix).first(where: { $0 >= min && $0 <= max }) {
                return value
            }
        }
        return nil
    }

    private func extractFractions(from text: String) -> [Double] {
        let pattern = #"(?<!\d)(\d{1,2})\s+(\d{1,2})\s*/\s*(\d{1,2})(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges == 4,
                  let whole = Double(nsText.substring(with: match.range(at: 1))),
                  let numerator = Double(nsText.substring(with: match.range(at: 2))),
                  let denominator = Double(nsText.substring(with: match.range(at: 3))),
                  denominator > 0
            else { return nil }
            return whole + numerator / denominator
        }
    }

    private func parseDecimal(beforeKeywords keywords: [String], in text: String, min: Double, max: Double) -> Double? {
        let lowercased = text.lowercased()
        let lines = lowercased.components(separatedBy: .newlines)

        for keyword in keywords {
            for line in lines where line.contains(keyword.lowercased()) {
                if let value = extractNumbers(from: line).last(where: { $0 >= min && $0 <= max }) {
                    return value
                }
            }
        }

        for keyword in keywords {
            guard let range = lowercased.range(of: keyword.lowercased()) else { continue }
            let prefix = String(lowercased[..<range.upperBound].suffix(60))
            if let match = extractNumbers(from: prefix).last(where: { $0 >= min && $0 <= max }) {
                return match
            }
        }
        return nil
    }

    private func bestDecimalCandidate(in text: String, min: Double, max: Double) -> Double? {
        extractNumbers(from: text).first(where: { $0 >= min && $0 <= max })
    }

    private func normalizeNumber(_ raw: String) -> Double? {
        let compact = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let commaCount = compact.filter { $0 == "," }.count
        let dotCount = compact.filter { $0 == "." }.count

        if commaCount > 0 && dotCount > 0 {
            let decimalSeparator = compact.lastIndex(where: { $0 == "," || $0 == "." })
            let normalized = compact.enumerated().compactMap { index, character -> Character? in
                let stringIndex = compact.index(compact.startIndex, offsetBy: index)
                if character == "," || character == "." {
                    return stringIndex == decimalSeparator ? "." : nil
                }
                return character
            }
            return Double(String(normalized))
        }

        if commaCount + dotCount == 1, let separator = compact.first(where: { $0 == "," || $0 == "." }) {
            let parts = compact.split(separator: separator, omittingEmptySubsequences: false)
            if parts.count == 2,
               parts[0].count <= 3,
               parts[1].count == 3 {
                return Double(parts.joined())
            }
            return Double(compact.replacingOccurrences(of: ",", with: "."))
        }

        if commaCount > 1 || dotCount > 1 {
            let separator: Character = commaCount > 1 ? "," : "."
            let parts = compact.split(separator: separator, omittingEmptySubsequences: false)
            if parts.dropFirst().allSatisfy({ $0.count == 3 }) {
                return Double(parts.joined())
            }
            let decimalSeparator = compact.lastIndex(of: separator)
            let normalized = compact.enumerated().compactMap { index, character -> Character? in
                let stringIndex = compact.index(compact.startIndex, offsetBy: index)
                if character == separator {
                    return stringIndex == decimalSeparator ? "." : nil
                }
                return character
            }
            return Double(String(normalized))
        }

        return Double(compact.replacingOccurrences(of: " ", with: ""))
    }
}

struct FillUpTextParseResult {
    var gallons: Double?
    var pricePerGallon: Double?
    var totalCost: Double?
    var odometerMiles: Double?
    var tripMiles: Double?
    var fuelLevelRemaining: Double?
}

struct SnapshotTextParseResult {
    var odometerMiles: Double?
    var tripMiles: Double?
    var fuelLevelRemaining: Double?
}
