import SwiftData
import SwiftUI

enum AppCopy {
    enum Language: Equatable {
        case spanish
        case english
    }

    static func language(for locale: Locale? = nil) -> Language {
        let identifier = locale?.identifier
            ?? UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first
            ?? Locale.autoupdatingCurrent.identifier
        let code = Locale(identifier: identifier).language.languageCode?.identifier
            ?? identifier.split(separator: "_").first.map(String.init)
        return code == "es" ? .spanish : .english
    }

    static func text(_ spanish: String, _ english: String, locale: Locale? = nil) -> String {
        language(for: locale) == .spanish ? spanish : english
    }

    static var dashboard: String { "Dashboard" }
    static var capture: String { text("Capturar", "Capture") }
    static var history: String { text("Historial", "History") }
    static var vehicles: String { text("Vehiculos", "Vehicles") }
    static var settings: String { text("Ajustes", "Settings") }
    static var camera: String { text("Cámara", "Camera") }
    static var photos: String { text("Fotos", "Photos") }
    static var remove: String { text("Quitar", "Remove") }
    static var noImage: String { text("Sin imagen", "No image") }
    static var next: String { text("Siguiente", "Next") }
    static var back: String { text("Atrás", "Back") }
    static var save: String { text("Guardar", "Save") }
    static var analyzing: String { text("Analizando…", "Analyzing…") }
    static var vehicle: String { text("Vehículo", "Vehicle") }
    static var location: String { text("Usar ubicación actual", "Use current location") }
    static var locationHint: String {
        text("Opcional. Solicita acceso a la ubicación sólo al tocarlo.",
             "Optional. Requests location access only when you tap it.")
    }
    static var reminder: String { text("Recordatorio", "Reminder") }
    static var notificationPermission: String {
        text("Activar recordatorios", "Enable reminders")
    }
    static var notificationHint: String {
        text("Solicita permiso de notificaciones sólo al tocarlo.",
             "Requests notification permission only when you tap it.")
    }

    static func photoActionHint(for title: String) -> String {
        text("Añade una foto de \(title.lowercased()) desde la cámara o tu biblioteca.",
             "Add a \(title.lowercased()) photo from the camera or your library.")
    }

    static func photoPreview(for title: String, hasImage: Bool) -> String {
        hasImage
            ? text("Foto de \(title) seleccionada.", "Selected \(title) photo.")
            : text("Aún no hay foto de \(title).", "No \(title) photo yet.")
    }
}

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label(AppCopy.dashboard, systemImage: "chart.xyaxis.line")
            }
            .accessibilityIdentifier("tab.dashboard")

            NavigationStack {
                CaptureHomeView()
            }
            .tabItem {
                Label(AppCopy.capture, systemImage: "camera.viewfinder")
            }
            .accessibilityIdentifier("tab.capture")

            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label(AppCopy.history, systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            }
            .accessibilityIdentifier("tab.history")

            NavigationStack {
                VehiclesView()
            }
            .tabItem {
                Label(AppCopy.vehicles, systemImage: "car.side")
            }
            .accessibilityIdentifier("tab.vehicles")

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(AppCopy.settings, systemImage: "gearshape")
            }
            .accessibilityIdentifier("tab.settings")
        }
        .tint(Color(red: 0.15, green: 0.45, blue: 0.28))
        .task {
            _ = try? LocalDataRepairService.repairReceiptDecimalArtifacts(in: modelContext)
        }
    }
}
