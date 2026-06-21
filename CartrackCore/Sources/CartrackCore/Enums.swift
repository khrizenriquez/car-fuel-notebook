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
