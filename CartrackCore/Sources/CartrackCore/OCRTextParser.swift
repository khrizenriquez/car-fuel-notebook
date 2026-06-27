import Foundation

struct OCRTextParser {
    func parseFillUp(invoiceText: String, odometerText: String, fuelLevelText: String, fuelScaleMax: Double) -> FillUpTextParseResult {
        let lineItem = parseFuelLineItem(from: invoiceText)
        return FillUpTextParseResult(
            gallons: lineItem?.gallons ?? parseGallons(from: invoiceText),
            pricePerGallon: lineItem?.pricePerGallon ?? parsePricePerGallon(from: invoiceText),
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
        parseFuelLineItem(from: text)?.gallons ??
        parseDecimal(afterKeywords: ["galones", "gallons", "cantidad", "cant. gal", "cant gal", "cant", "despachado", "volumen"], in: text, min: 1, max: 30)
            ?? parseDecimal(beforeKeywords: ["galones", "gallons", "gals", "gal"], in: text, min: 1, max: 30)
            ?? bestDecimalCandidate(in: text, min: 1, max: 30)
    }

    func parsePricePerGallon(from text: String) -> Double? {
        parseFuelLineItem(from: text)?.pricePerGallon ??
        parseDecimal(afterKeywords: ["precio por galon", "precio unitario", "precio x galon", "precio gal", "p/gal", "p.gal", "p.u.", "p/u", "precio"], in: text, min: 10, max: 80)
            ?? bestDecimalCandidate(in: text, min: 10, max: 80)
    }

    func parseTotalCost(from text: String) -> Double? {
        parseTemporarySocialSupportTotal(from: text)
            ?? parseFuelLineItem(from: text)?.totalCost
            ?? parseExplicitTotalLine(from: text)
            ?? parseDecimal(
                afterKeywords: ["total pagado", "total a pagar", "importe"],
                in: text,
                min: 20,
                max: 5_000
            )
            ?? bestDecimalCandidate(in: text, min: 20, max: 5_000)
    }

    func parseLargestMileage(from text: String) -> Double? {
        parseInstrumentClusterOdometer(from: text)
            ??
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
        parseInstrumentClusterTrip(from: text)
            ??
        extractNumbers(from: text)
            .filter { $0 >= 0 && $0 < 2_000 && $0.truncatingRemainder(dividingBy: 1) != 0 }
            .sorted(by: >)
            .first
    }

    func parseFuelLevel(from text: String, fuelScaleMax: Double) -> Double? {
        guard let value = parseFraction(afterKeywords: ["espacios restantes", "spaces remaining", "quedan", "restante", "nivel", "fuel level"], in: text, min: 0, max: fuelScaleMax)
            ?? parseDecimal(afterKeywords: ["espacios restantes", "spaces remaining", "quedan", "restante", "nivel", "fuel level"], in: text, min: 0, max: fuelScaleMax)
            ?? parseDecimal(beforeKeywords: ["espacios", "spaces", "barras"], in: text, min: 0, max: fuelScaleMax)
        else { return nil }
        return FuelLevelScale.normalize(value, maxValue: fuelScaleMax)
    }

    func extractNumbers(from text: String) -> [Double] {
        let pattern = #"(?<!\d)(?:\d{1,3}(?:[.,\s]\d{3})+(?:[.,]\d+)?|\d+(?:[.,]\d+)?)(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            normalizeNumber(nsText.substring(with: match.range))
        }
    }

    private func parseDecimal(
        afterKeywords keywords: [String],
        in text: String,
        min: Double,
        max: Double,
        excludingLinesContaining excludedTerms: [String] = []
    ) -> Double? {
        let lowercased = text.lowercased()
        let lines = lowercased.components(separatedBy: .newlines)

        for keyword in keywords {
            for line in lines where line.contains(keyword.lowercased()) {
                guard !containsExcludedTerm(line, excludedTerms: excludedTerms) else { continue }
                if let value = extractNumbers(from: line).first(where: { $0 >= min && $0 <= max }) {
                    return value
                }
            }
        }

        for keyword in keywords {
            guard let range = lowercased.range(of: keyword.lowercased()) else { continue }
            let suffix = String(lowercased[range.lowerBound...].prefix(60))
            guard !containsExcludedTerm(suffix, excludedTerms: excludedTerms) else { continue }
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

    private func parseFuelLineItem(from text: String) -> FuelLineItem? {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let lowercased = line.lowercased()
            let numbers = extractNumbers(from: line)
            guard numbers.count >= 3,
                  lowercased.range(of: #"premium|regular|super|diesel|gasolina|combustible|sc-"#, options: .regularExpression) != nil
            else { continue }

            for index in numbers.indices.dropLast(2) {
                let gallons = numbers[index]
                let price = numbers[index + 1]
                let total = numbers[index + 2]
                guard gallons >= 1, gallons <= 30,
                      price >= 10, price <= 80,
                      total >= 20, total <= 5_000
                else { continue }

                let expectedTotal = gallons * price
                let tolerance = max(0.05, expectedTotal * 0.01)
                if abs(expectedTotal - total) <= tolerance {
                    return FuelLineItem(gallons: gallons, pricePerGallon: price, totalCost: total)
                }
            }
        }
        return nil
    }

    private func parseTemporarySocialSupportTotal(from text: String) -> Double? {
        let lines = text.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let lowercased = line.lowercased()
            guard lowercased.contains("sin apoyo")
                    || lowercased.contains("apoyo social")
                    || lowercased.contains("temporal")
            else { continue }

            let window = lines[index..<min(lines.count, index + 4)].joined(separator: " ")
            if let value = extractNumbers(from: window).last(where: { $0 >= 20 && $0 <= 5_000 }) {
                return value
            }
        }

        let normalizedText = text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined(separator: " ")
        guard let range = normalizedText.range(of: "monto total a pagar sin apoyo social temporal") else {
            return nil
        }
        let suffix = String(normalizedText[range.lowerBound...].prefix(120))
        return extractNumbers(from: suffix).last(where: { $0 >= 20 && $0 <= 5_000 })
    }

    private func parseExplicitTotalLine(from text: String) -> Double? {
        let lines = text.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let lowercased = line.lowercased()
            guard lowercased.contains("total"),
                  !isNonPaidTotalLine(lowercased)
            else { continue }

            if let value = extractNumbers(from: line).last(where: { $0 >= 20 && $0 <= 5_000 }) {
                return value
            }

            var lookaheadValues: [Double] = []
            let lookahead = lines.dropFirst(index + 1).prefix(5)
            for nextLine in lookahead {
                let nextLowercased = nextLine.lowercased()
                guard !isNonPaidTotalLine(nextLowercased) else { break }
                lookaheadValues.append(contentsOf: extractNumbers(from: nextLine).filter { $0 >= 20 && $0 <= 5_000 })
            }
            if let value = lookaheadValues.last {
                return value
            }
        }
        return nil
    }

    private func isNonPaidTotalLine(_ lowercasedLine: String) -> Bool {
        containsExcludedTerm(
            lowercasedLine,
            excludedTerms: ["sin apoyo", "apoyo social", "impuesto", "idp", "cantidad", "descripcion", "precio u"]
        )
    }

    private func containsExcludedTerm(_ text: String, excludedTerms: [String]) -> Bool {
        excludedTerms.contains { text.contains($0) }
    }

    private func parseInstrumentClusterOdometer(from text: String) -> Double? {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            guard let milesRange = line.range(of: #"miles?|mils?|millas?"#, options: [.regularExpression, .caseInsensitive]) else { continue }
            let prefix = String(line[..<milesRange.lowerBound])
            if let value = instrumentOdometerCandidate(from: prefix) {
                return value
            }
        }
        return nil
    }

    private func parseInstrumentClusterTrip(from text: String) -> Double? {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            guard let milesRange = line.range(of: #"miles?|mils?|millas?"#, options: [.regularExpression, .caseInsensitive]) else { continue }
            let suffix = String(line[milesRange.upperBound...])
            if let value = instrumentTripCandidate(from: suffix) {
                return value
            }
        }
        return nil
    }

    private func instrumentOdometerCandidate(from text: String) -> Double? {
        extractNumbers(from: correctedSevenSegmentText(text))
            .filter { $0 >= 10_000 && $0 <= 999_999 }
            .max()
    }

    private func instrumentTripCandidate(from text: String) -> Double? {
        let corrected = correctedSevenSegmentText(text)
        if let decimal = extractNumbers(from: corrected)
            .first(where: { $0 >= 0 && $0 < 2_000 && $0.truncatingRemainder(dividingBy: 1) != 0 }) {
            return decimal
        }

        let pattern = #"(?<!\d)0(\d{2,3})(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = corrected as NSString
        return regex.matches(in: corrected, range: NSRange(location: 0, length: nsText.length))
            .compactMap { match -> Double? in
                guard match.numberOfRanges == 2,
                      let raw = Double(nsText.substring(with: match.range(at: 1)))
                else { return nil }
                let value = raw / 10
                return value >= 0 && value < 2_000 ? value : nil
            }
            .first
    }

    private func correctedSevenSegmentText(_ text: String) -> String {
        var corrected = ""
        for character in text {
            switch character {
            case "I", "l", "|", "!":
                corrected.append("1")
            case "O", "o", "D", "Q":
                corrected.append("0")
            case "S", "s":
                corrected.append("5")
            case "B":
                corrected.append("8")
            default:
                corrected.append(character)
            }
        }
        return corrected
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

private struct FuelLineItem {
    let gallons: Double
    let pricePerGallon: Double
    let totalCost: Double
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
