import Foundation

struct EventIntegrityReading: Equatable {
    let id: UUID
    let occurredAt: Date
    let odometerKilometers: Decimal
    let tripKilometers: Decimal?
}

struct EventIntegrityInput {
    let reading: EventIntegrityReading
    let fuelLevelRemaining: Decimal
    let fuelScaleMax: Decimal
    let fuelScaleStep: Decimal
    let financial: FinancialValues?
    let overrideReason: String

    struct FinancialValues {
        let gallons: Decimal
        let unitPrice: Decimal
        let totalCost: Decimal
    }
}

struct EventIntegrityResult: Equatable {
    let tripResetDetected: Bool
    let odometerOverrideUsed: Bool
}

enum EventIntegrityError: String, Error, LocalizedError {
    case invalidOdometer = "odometer.invalid"
    case odometerRegression = "odometer.regression"
    case invalidTrip = "trip.invalid"
    case invalidFuelLevel = "fuelLevel.invalidStep"
    case invalidFinancial = "financial.invalid"
    case inconsistentFinancial = "financial.inconsistent"

    var code: String { rawValue }

    var errorDescription: String? {
        switch self {
        case .invalidOdometer: "El odómetro debe ser un número positivo."
        case .odometerRegression: "El odómetro contradice otro registro de este vehículo. Corrige el valor o explica la corrección en ‘Motivo de corrección del odómetro’."
        case .invalidTrip: "El trip no puede ser negativo ni mayor que el odómetro."
        case .invalidFuelLevel: "El nivel debe estar dentro de la escala y coincidir con un paso del medidor."
        case .invalidFinancial: "Galones, precio y total deben ser mayores que cero."
        case .inconsistentFinancial: "Galones × precio no coincide con el total (tolerancia Q0.05). Revisa los tres valores."
        }
    }
}

enum EventIntegrityPolicy {
    static let defaultFinancialTolerance = Decimal(string: "0.05")!

    static func validate(_ input: EventIntegrityInput,
                         among readings: [EventIntegrityReading],
                         financialTolerance: Decimal = defaultFinancialTolerance) throws -> EventIntegrityResult {
        let current = input.reading
        guard current.odometerKilometers > 0 else { throw EventIntegrityError.invalidOdometer }
        if let trip = current.tripKilometers,
           trip < 0 || trip > current.odometerKilometers {
            throw EventIntegrityError.invalidTrip
        }
        guard input.fuelScaleMax > 0, input.fuelScaleStep > 0,
              input.fuelLevelRemaining >= 0,
              input.fuelLevelRemaining <= input.fuelScaleMax else {
            throw EventIntegrityError.invalidFuelLevel
        }
        let steps = input.fuelLevelRemaining / input.fuelScaleStep
        var roundedSteps = Decimal()
        var mutableSteps = steps
        NSDecimalRound(&roundedSteps, &mutableSteps, 0, .plain)
        guard absolute(steps - roundedSteps) < Decimal(string: "0.0001")! else {
            throw EventIntegrityError.invalidFuelLevel
        }
        if let financial = input.financial {
            guard financial.gallons > 0, financial.unitPrice > 0, financial.totalCost > 0 else {
                throw EventIntegrityError.invalidFinancial
            }
            guard absolute(financial.gallons * financial.unitPrice - financial.totalCost) <= financialTolerance else {
                throw EventIntegrityError.inconsistentFinancial
            }
        }

        let others = readings.filter { $0.id != current.id }
        let before = others.filter { $0.occurredAt < current.occurredAt }
            .max { $0.occurredAt < $1.occurredAt }
        let after = others.filter { $0.occurredAt > current.occurredAt }
            .min { $0.occurredAt < $1.occurredAt }
        let regression = before.map { current.odometerKilometers < $0.odometerKilometers } == true
            || after.map { current.odometerKilometers > $0.odometerKilometers } == true
        let reason = input.overrideReason.trimmingCharacters(in: .whitespacesAndNewlines)
        if regression && reason.count < 8 { throw EventIntegrityError.odometerRegression }
        return EventIntegrityResult(
            tripResetDetected: before?.tripKilometers.flatMap { prior in
                current.tripKilometers.map { $0 < prior }
            } ?? false,
            odometerOverrideUsed: regression
        )
    }

    private static func absolute(_ value: Decimal) -> Decimal { value < 0 ? -value : value }
}
