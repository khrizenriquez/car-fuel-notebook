import Foundation

enum CartrackFormatters {
    static let currencyGTQ: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "GTQ"
        formatter.currencySymbol = "Q"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()

    static let decimal2: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    static func currency(_ value: Double) -> String {
        currencyGTQ.string(from: NSNumber(value: value)) ?? "Q\(value)"
    }

    static func decimal(_ value: Double, suffix: String = "") -> String {
        let valueString = decimal2.string(from: NSNumber(value: value)) ?? String(value)
        return suffix.isEmpty ? valueString : "\(valueString) \(suffix)"
    }
}
