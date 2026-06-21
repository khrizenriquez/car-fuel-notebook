import Foundation

enum UnitConversion {
    static let kilometersPerMile = 1.609344

    static func milesToKilometers(_ miles: Double) -> Double {
        miles * kilometersPerMile
    }

    static func kilometersToMiles(_ kilometers: Double) -> Double {
        kilometers / kilometersPerMile
    }
}
