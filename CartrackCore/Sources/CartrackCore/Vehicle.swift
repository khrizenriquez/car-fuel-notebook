import Foundation
import SwiftData

@Model
final class Vehicle {
    @Attribute(.unique) var id: UUID
    var name: String
    var make: String
    var modelName: String
    var year: Int
    var fuelScaleMax: Double
    var fuelScaleStep: Double
    var notes: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        make: String,
        modelName: String,
        year: Int,
        fuelScaleMax: Double = FuelLevelScale.defaultMax,
        fuelScaleStep: Double = FuelLevelScale.defaultStep,
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.make = make
        self.modelName = modelName
        self.year = year
        self.fuelScaleMax = fuelScaleMax
        self.fuelScaleStep = fuelScaleStep
        self.notes = notes
        self.createdAt = createdAt
    }
}

extension Vehicle {
    var displayName: String {
        [Optional(name), Optional(make), Optional(modelName), year == 0 ? nil : String(year)]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: " ")
    }
}
