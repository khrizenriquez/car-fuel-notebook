import Foundation
import SwiftData

@MainActor
enum EventIntegrityService {
    static func validate(_ input: EventIntegrityInput, vehicleID: UUID,
                         in context: ModelContext) throws -> EventIntegrityResult {
        let fills = try context.fetch(FetchDescriptor<FuelFillEvent>())
            .filter { $0.vehicle?.id == vehicleID }
            .map { EventIntegrityReading(id: $0.id, occurredAt: $0.date,
                                         odometerKilometers: Decimal(string: String($0.odometerKilometers)) ?? 0,
                                         tripKilometers: $0.tripKilometers.flatMap { Decimal(string: String($0)) }) }
        let snapshots = try context.fetch(FetchDescriptor<SnapshotEvent>())
            .filter { $0.vehicle?.id == vehicleID }
            .map { EventIntegrityReading(id: $0.id, occurredAt: $0.date,
                                         odometerKilometers: Decimal(string: String($0.odometerKilometers)) ?? 0,
                                         tripKilometers: $0.tripKilometers.flatMap { Decimal(string: String($0)) }) }
        return try EventIntegrityPolicy.validate(input, among: fills + snapshots)
    }

    /// Reuses the local field-evidence ledger for a user-authorized correction. No photo is copied or synced.
    static func recordOverride(_ result: EventIntegrityResult, input: EventIntegrityInput,
                               eventID: UUID, sessionID: UUID?, in context: ModelContext) {
        guard result.odometerOverrideUsed else { return }
        context.insert(OCRFieldEvidence(
            sessionID: sessionID ?? eventID, ownerEventID: eventID,
            fieldRawValue: CaptureField.odometerKilometers.rawValue,
            rawText: input.overrideReason.trimmingCharacters(in: .whitespacesAndNewlines),
            normalizedValue: NSDecimalNumber(decimal: input.reading.odometerKilometers).stringValue,
            unit: "km", confidenceDecimal: "1", confidenceBandRawValue: "manual",
            validationCodes: ["odometer.regression", "override.approved"],
            wasManuallyCorrected: true, algorithmVersion: "integrity-override-v1"
        ))
    }
}
