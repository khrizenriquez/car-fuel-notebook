import Foundation

enum CaptureImageKind: String, Codable, CaseIterable, Identifiable {
    case invoice
    case odometer
    case fuelLevel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .invoice: "Factura"
        case .odometer: "Odometro"
        case .fuelLevel: "Nivel de tanque"
        }
    }
}

enum HistoryEventKind: String, CaseIterable, Identifiable {
    case fillUp
    case snapshot

    var id: String { rawValue }
}

enum ImageOwnerKind: String, Codable {
    case fillUp
    case snapshot
}

enum MonthlyAllocationMode: String, CaseIterable, Identifiable {
    case finalFillMonth
    case prorated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .finalFillMonth: "Mes cierre"
        case .prorated: "Prorrateado"
        }
    }
}

struct EventCoordinate: Equatable {
    let latitude: Double
    let longitude: Double
}

enum EventLocationPolicy {
    static func resolvedCoordinate(
        currentLatitude: Double?,
        currentLongitude: Double?,
        existingLatitude: Double?,
        existingLongitude: Double?
    ) -> EventCoordinate? {
        if let currentLatitude, let currentLongitude {
            return EventCoordinate(latitude: currentLatitude, longitude: currentLongitude)
        }

        if let existingLatitude, let existingLongitude {
            return EventCoordinate(latitude: existingLatitude, longitude: existingLongitude)
        }

        return nil
    }
}
