import Foundation

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var asDouble: Double? {
        Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }
}

extension Double {
    func nonZeroOrDefault(_ value: Double) -> Double {
        self == 0 ? value : self
    }
}
