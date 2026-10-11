import Foundation

enum UnitConversion {
    static let kilometersPerMile = 1.609344
    static let litersPerGallon = 3.785411784

    static func milesToKilometers(_ miles: Double) -> Double {
        miles * kilometersPerMile
    }

    static func kilometersToMiles(_ kilometers: Double) -> Double {
        kilometers / kilometersPerMile
    }

    static func gallonsToLiters(_ gallons: Double) -> Double {
        gallons * litersPerGallon
    }

    static func litersToGallons(_ liters: Double) -> Double {
        liters / litersPerGallon
    }
}
