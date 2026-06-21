import Foundation
import SwiftData

@Model
final class SnapshotEvent {
    @Attribute(.unique) var id: UUID
    var date: Date
    var odometerMilesOriginal: Double?
    var odometerKilometers: Double
    var tripMilesOriginal: Double?
    var tripKilometers: Double?
    var fuelLevelRemaining: Double
    var latitude: Double?
    var longitude: Double?
    var notes: String
    var odometerOCRText: String
    var fuelLevelOCRText: String
    var createdAt: Date
    var updatedAt: Date

    var vehicle: Vehicle?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        vehicle: Vehicle? = nil,
        odometerMilesOriginal: Double? = nil,
        odometerKilometers: Double = 0,
        tripMilesOriginal: Double? = nil,
        tripKilometers: Double? = nil,
        fuelLevelRemaining: Double = FuelLevelScale.defaultMax,
        latitude: Double? = nil,
        longitude: Double? = nil,
        notes: String = "",
        odometerOCRText: String = "",
        fuelLevelOCRText: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.vehicle = vehicle
        self.odometerMilesOriginal = odometerMilesOriginal
        self.odometerKilometers = odometerKilometers
        self.tripMilesOriginal = tripMilesOriginal
        self.tripKilometers = tripKilometers
        self.fuelLevelRemaining = fuelLevelRemaining
        self.latitude = latitude
        self.longitude = longitude
        self.notes = notes
        self.odometerOCRText = odometerOCRText
        self.fuelLevelOCRText = fuelLevelOCRText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
