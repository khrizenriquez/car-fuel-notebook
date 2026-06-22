import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("settings.reminder.enabled") private var reminderEnabled = true
    @AppStorage("settings.reminder.hours") private var reminderHours = 72.0
    @State private var isShowingResetConfirmation = false
    @State private var resetError: String?

    var body: some View {
        Form {
            Section("Persistencia") {
                Text("La base de datos local y las imagenes deben sobrevivir actualizaciones normales de la app.")
                    .foregroundStyle(.secondary)
                Text("El borrado total solo ocurre si tu lo confirmas aqui.")
                    .foregroundStyle(.secondary)
            }

            Section("Recordatorios") {
                Toggle("Activar recordatorio por inactividad", isOn: $reminderEnabled)
                VStack(alignment: .leading) {
                    HStack {
                        Text("Horas sin actividad")
                        Spacer()
                        Text(CartrackFormatters.decimal(reminderHours))
                    }
                    Slider(value: $reminderHours, in: 12...168, step: 12)
                }
                Button("Solicitar permisos de notificacion") {
                    Task { await ReminderService.shared.requestAuthorization() }
                }
            }

            Section("Datos de prueba") {
                Button("Reset total", role: .destructive) {
                    isShowingResetConfirmation = true
                }
                .accessibilityIdentifier("settings.reset")
                Text("El reset elimina vehiculos, eventos, imagenes y ajustes mensuales.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Ajustes")
        .confirmationDialog("Esto eliminara todos los datos.", isPresented: $isShowingResetConfirmation) {
            Button("Borrar todo", role: .destructive, action: resetAll)
                .accessibilityIdentifier("settings.reset.confirm")
            Button("Cancelar", role: .cancel) {}
        }
        .alert("No se pudo resetear", isPresented: Binding(get: { resetError != nil }, set: { _ in resetError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resetError ?? "")
        }
        .onChange(of: reminderEnabled) { _, enabled in
            Task {
                if enabled {
                    await ReminderService.shared.refreshInactivityReminder(isEnabled: true, afterHours: reminderHours)
                } else {
                    await ReminderService.shared.refreshInactivityReminder(isEnabled: false, afterHours: reminderHours)
                }
            }
        }
        .onChange(of: reminderHours) { _, hours in
            Task {
                if reminderEnabled {
                    await ReminderService.shared.refreshInactivityReminder(isEnabled: true, afterHours: hours)
                }
            }
        }
    }

    private func resetAll() {
        do {
            try ResetService.resetAll(context: modelContext)
            ReminderService.shared.cancelInactivityReminder()
        } catch {
            resetError = error.localizedDescription
        }
    }
}
