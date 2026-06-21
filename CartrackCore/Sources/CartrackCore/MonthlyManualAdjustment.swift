import Foundation
import SwiftData

@Model
final class MonthlyManualAdjustment {
    @Attribute(.unique) var id: UUID
    var monthStart: Date
    var manualDistanceMiles: Double?
    var manualDistanceKilometers: Double?
    var note: String
    var createdAt: Date
    var updatedAt: Date

    var vehicle: Vehicle?

    init(
        id: UUID = UUID(),
        monthStart: Date,
        vehicle: Vehicle? = nil,
        manualDistanceMiles: Double? = nil,
        manualDistanceKilometers: Double? = nil,
        note: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.monthStart = monthStart
        self.vehicle = vehicle
        self.manualDistanceMiles = manualDistanceMiles
        self.manualDistanceKilometers = manualDistanceKilometers
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
