import SwiftData
import SwiftUI

struct VehicleFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let vehicle: Vehicle?

    @State private var name = ""
    @State private var make = ""
    @State private var modelName = ""
    @State private var year = ""
    @State private var fuelScaleMax = FuelLevelScale.defaultMax
    @State private var fuelScaleStep = FuelLevelScale.defaultStep
    @State private var notes = ""

    init(vehicle: Vehicle? = nil) {
        self.vehicle = vehicle
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identidad") {
                    TextField("Nombre visible", text: $name)
                        .accessibilityIdentifier("vehicle.name")
                    TextField("Marca", text: $make)
                        .accessibilityIdentifier("vehicle.make")
                    TextField("Modelo", text: $modelName)
                        .accessibilityIdentifier("vehicle.model")
                    TextField("Ano", text: $year)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("vehicle.year")
                }

                Section("Tanque") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Escala maxima")
                            Spacer()
                            Text(CartrackFormatters.decimal(fuelScaleMax))
                        }
                        Slider(value: $fuelScaleMax, in: 1...12, step: 0.25)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Paso")
                            Spacer()
                            Text(CartrackFormatters.decimal(fuelScaleStep))
                        }
                        Slider(value: $fuelScaleStep, in: 0.25...1, step: 0.25)
                    }
                }

                Section("Notas") {
                    TextField("Detalles del vehiculo", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(vehicle == nil ? "Nuevo vehiculo" : "Editar vehiculo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                        .accessibilityIdentifier("vehicle.save")
                }
            }
            .onAppear(perform: loadExistingData)
        }
    }

    private func save() {
        let target = vehicle ?? Vehicle(
            name: name.trimmed,
            make: make.trimmed,
            modelName: modelName.trimmed,
            year: Int(year) ?? 0
        )
        target.name = name.trimmed
        target.make = make.trimmed
        target.modelName = modelName.trimmed
        target.year = Int(year) ?? 0
        target.fuelScaleMax = FuelLevelScale.normalize(fuelScaleMax, maxValue: 12, step: 0.25)
        target.fuelScaleStep = FuelLevelScale.normalize(fuelScaleStep, maxValue: 1, step: 0.25)
        target.notes = notes.trimmed
        if vehicle == nil {
            modelContext.insert(target)
        }
        try? modelContext.save()
        dismiss()
    }

    private func loadExistingData() {
        name = vehicle?.name ?? ""
        make = vehicle?.make ?? ""
        modelName = vehicle?.modelName ?? ""
        year = vehicle.map { String($0.year) } ?? ""
        fuelScaleMax = vehicle?.fuelScaleMax ?? FuelLevelScale.defaultMax
        fuelScaleStep = vehicle?.fuelScaleStep ?? FuelLevelScale.defaultStep
        notes = vehicle?.notes ?? ""
    }
}
