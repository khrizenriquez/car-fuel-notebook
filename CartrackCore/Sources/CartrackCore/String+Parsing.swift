import Foundation

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var asDouble: Double? {
        normalizedNumericValue
    }

    var asDecimalDouble: Double? {
        normalizedDecimalValue
    }

    private var normalizedNumericValue: Double? {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard !compact.isEmpty else { return nil }

        let commaCount = compact.filter { $0 == "," }.count
        let dotCount = compact.filter { $0 == "." }.count

        if commaCount > 0 && dotCount > 0 {
            let decimalSeparator = compact.lastIndex(where: { $0 == "," || $0 == "." })
            let normalized = compact.indices.compactMap { index -> Character? in
                let character = compact[index]
                if character == "," || character == "." {
                    return index == decimalSeparator ? "." : nil
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
            let normalized = compact.indices.compactMap { index -> Character? in
                let character = compact[index]
                if character == separator {
                    return index == decimalSeparator ? "." : nil
                }
                return character
            }
            return Double(String(normalized))
        }

        return Double(compact)
    }

    private var normalizedDecimalValue: Double? {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard !compact.isEmpty else { return nil }

        let commaCount = compact.filter { $0 == "," }.count
        let dotCount = compact.filter { $0 == "." }.count

        if commaCount > 0 && dotCount > 0 {
            return normalizedNumericValue
        }

        if commaCount + dotCount == 1 {
            return Double(compact.replacingOccurrences(of: ",", with: "."))
        }

        return normalizedNumericValue
    }
}

extension Double {
    func nonZeroOrDefault(_ value: Double) -> Double {
        self == 0 ? value : self
    }
}
