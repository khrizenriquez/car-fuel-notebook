import SwiftData
import SwiftUI

struct MonthlyAdjustmentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let vehicle: Vehicle
    let monthStart: Date
    let existingAdjustment: MonthlyManualAdjustment?

    @State private var miles = ""
    @State private var kilometers = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Distancia manual") {
                    TextField("Millas manuales", text: $miles)
                        .keyboardType(.decimalPad)
                    TextField("Kilometros manuales", text: $kilometers)
                        .keyboardType(.decimalPad)
                    Text("Puedes dejar solo uno de los dos valores. Si ambos existen, se prioriza kilometros.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Nota") {
                    TextField("Contexto o correccion", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Ajuste mensual")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                }
            }
            .onAppear {
                miles = existingAdjustment?.manualDistanceMiles.map { String($0) } ?? ""
                kilometers = existingAdjustment?.manualDistanceKilometers.map { String($0) } ?? ""
                note = existingAdjustment?.note ?? ""
            }
        }
    }

    private func save() {
        let adjustment = existingAdjustment ?? MonthlyManualAdjustment(monthStart: monthStart, vehicle: vehicle)
        adjustment.monthStart = monthStart
        adjustment.vehicle = vehicle
        adjustment.manualDistanceMiles = miles.asDouble
        adjustment.manualDistanceKilometers = kilometers.asDouble
        adjustment.note = note.trimmed
        adjustment.updatedAt = .now
        if existingAdjustment == nil {
            modelContext.insert(adjustment)
        }
        try? modelContext.save()
        dismiss()
    }
}
