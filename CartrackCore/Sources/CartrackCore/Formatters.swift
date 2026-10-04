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

    static let fuelGallons: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    static let distance: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
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

    static func gallons(_ value: Double, suffix: String = "gal") -> String {
        let valueString = fuelGallons.string(from: NSNumber(value: value)) ?? String(value)
        return suffix.isEmpty ? valueString : "\(valueString) \(suffix)"
    }

    static func distancePrimary(_ kilometers: Double, unit: OdometerUnit) -> String {
        switch unit {
        case .miles:
            distanceValue(UnitConversion.kilometersToMiles(kilometers), suffix: "mi")
        case .kilometers:
            distanceValue(kilometers, suffix: "km")
        }
    }

    static func distanceSecondary(_ kilometers: Double, unit: OdometerUnit) -> String {
        switch unit {
        case .miles:
            distanceValue(kilometers, suffix: "km")
        case .kilometers:
            distanceValue(UnitConversion.kilometersToMiles(kilometers), suffix: "mi")
        }
    }

    static func distancePair(_ kilometers: Double, unit: OdometerUnit) -> String {
        "\(distancePrimary(kilometers, unit: unit)) = \(distanceSecondary(kilometers, unit: unit))"
    }

    private static func distanceValue(_ value: Double, suffix: String) -> String {
        let valueString = distance.string(from: NSNumber(value: value)) ?? String(value)
        return "\(valueString) \(suffix)"
    }
}
