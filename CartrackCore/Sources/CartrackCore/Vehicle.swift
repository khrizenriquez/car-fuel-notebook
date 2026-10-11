import Foundation
import SwiftData

@Model
final class Vehicle {
    @Attribute(.unique) var id: UUID
    var name: String = ""
    var make: String = ""
    var modelName: String = ""
    var year: Int = 0
    var engine: String = ""
    var plate: String = ""
    var odometerUnitRawValue: String = OdometerUnit.miles.rawValue
    var tankCapacityGallons: Double = 14
    var fuelScaleMax: Double = FuelLevelScale.defaultMax
    var fuelScaleStep: Double = FuelLevelScale.defaultStep
    var fuelEconomyReferenceKilometersPerGallon: Double = 24.5
    var notes: String = ""
    var createdAt: Date = Date.now

    init(
        id: UUID = UUID(),
        name: String,
        make: String,
        modelName: String,
        year: Int,
        engine: String = "",
        plate: String = "",
        odometerUnit: OdometerUnit = .miles,
        tankCapacityGallons: Double = 14,
        fuelScaleMax: Double = FuelLevelScale.defaultMax,
        fuelScaleStep: Double = FuelLevelScale.defaultStep,
        fuelEconomyReferenceKilometersPerGallon: Double = 24.5,
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.make = make
        self.modelName = modelName
        self.year = year
        self.engine = engine
        self.plate = plate
        self.odometerUnitRawValue = odometerUnit.rawValue
        self.tankCapacityGallons = tankCapacityGallons
        self.fuelScaleMax = fuelScaleMax
        self.fuelScaleStep = fuelScaleStep
        self.fuelEconomyReferenceKilometersPerGallon = fuelEconomyReferenceKilometersPerGallon
        self.notes = notes
        self.createdAt = createdAt
    }
}

extension Vehicle {
    var odometerUnit: OdometerUnit {
        get { OdometerUnit(rawValue: odometerUnitRawValue) ?? .miles }
        set { odometerUnitRawValue = newValue.rawValue }
    }

    var fuelSegments: Int {
        Int(fuelScaleMax.rounded())
    }

    var displayName: String {
        [Optional(name), Optional(make), Optional(modelName), year == 0 ? nil : String(year)]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: " ")
    }
}
