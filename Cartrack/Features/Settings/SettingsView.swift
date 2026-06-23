import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    @AppStorage("settings.reminder.enabled") private var reminderEnabled = true
    @AppStorage("settings.reminder.hours") private var reminderHours = 72.0
    @State private var selectedResetVehicleID: UUID?
    @State private var isShowingResetConfirmation = false
    @State private var resetError: String?

    private var selectedResetVehicle: Vehicle? {
        vehicles.first(where: { $0.id == selectedResetVehicleID }) ?? vehicles.first
    }

    var body: some View {
        Form {
            Section("Persistencia") {
                Text("La base de datos local y las imagenes deben sobrevivir actualizaciones normales de la app.")
                    .foregroundStyle(.secondary)
                Text("El borrado de datos solo ocurre si tu lo confirmas aqui y no elimina vehiculos.")
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

            Section("Datos del vehiculo") {
                if vehicles.isEmpty {
                    Text("Agrega un vehiculo antes de borrar datos.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Vehiculo", selection: Binding(
                        get: { selectedResetVehicle?.id },
                        set: { selectedResetVehicleID = $0 }
                    )) {
                        ForEach(vehicles, id: \.id) { vehicle in
                            Text(vehicle.displayName).tag(Optional(vehicle.id))
                        }
                    }
                    .accessibilityIdentifier("settings.reset.vehicle")

                    Text("Vehiculo actual: \(selectedResetVehicle?.displayName ?? "N/A")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Borrar datos de este vehiculo", role: .destructive) {
                        isShowingResetConfirmation = true
                    }
                    .accessibilityIdentifier("settings.reset")

                    Text("Esto elimina llenados, snapshots, ajustes mensuales e imagenes del vehiculo seleccionado. El vehiculo y los datos de otros vehiculos se conservan.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Ajustes")
        .confirmationDialog(resetConfirmationTitle, isPresented: $isShowingResetConfirmation) {
            Button("Borrar datos", role: .destructive, action: resetSelectedVehicleData)
                .accessibilityIdentifier("settings.reset.confirm")
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("El vehiculo se conservara. Esta accion no toca otros vehiculos.")
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
        .onAppear(perform: ensureSelectedVehicle)
        .onChange(of: vehicles.map(\.id)) { _, _ in
            ensureSelectedVehicle()
        }
    }

    private var resetConfirmationTitle: String {
        guard let vehicle = selectedResetVehicle else {
            return "No hay vehiculo seleccionado."
        }
        return "Borrar datos de \(vehicle.displayName)?"
    }

    private func ensureSelectedVehicle() {
        guard selectedResetVehicle == nil else { return }
        selectedResetVehicleID = vehicles.first?.id
    }

    private func resetSelectedVehicleData() {
        guard let vehicle = selectedResetVehicle else {
            resetError = "Selecciona un vehiculo valido."
            return
        }

        do {
            try ResetService.resetData(for: vehicle, context: modelContext)
            ReminderService.shared.cancelInactivityReminder()
        } catch {
            resetError = error.localizedDescription
        }
    }
}
