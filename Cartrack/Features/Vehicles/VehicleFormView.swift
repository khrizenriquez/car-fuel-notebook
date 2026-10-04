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
    @State private var engine = ""
    @State private var plate = ""
    @State private var odometerUnit = OdometerUnit.miles
    @State private var tankCapacityGallons = ""
    @State private var fuelScaleMax = FuelLevelScale.defaultMax
    @State private var fuelScaleStep = FuelLevelScale.defaultStep
    @State private var fuelEconomyReferenceKilometersPerGallon = ""
    @State private var notes = ""
    @State private var saveError: String?

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
                    TextField("Motor (opcional)", text: $engine)
                        .accessibilityIdentifier("vehicle.engine")
                    TextField("Placa (opcional)", text: $plate)
                        .textInputAutocapitalization(.characters)
                        .accessibilityIdentifier("vehicle.plate")
                }

                Section("Medicion") {
                    Picker("Unidad del odometro", selection: $odometerUnit) {
                        ForEach(OdometerUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .accessibilityIdentifier("vehicle.odometerUnit")

                    TextField("Capacidad teorica (gal)", text: $tankCapacityGallons)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("vehicle.tankCapacity")
                }

                Section("Tanque") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Segmentos totales")
                            Spacer()
                            Text(CartrackFormatters.decimal(fuelScaleMax))
                        }
                        Stepper(value: $fuelScaleMax, in: 1...12, step: 1) {
                            Text("Ajustar segmentos")
                        }
                        .accessibilityIdentifier("vehicle.segments")
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Paso de ajuste")
                            Spacer()
                            Text(CartrackFormatters.decimal(fuelScaleStep))
                        }
                        Slider(value: $fuelScaleStep, in: 0.25...1, step: 0.25)
                    }
                }

                Section("Referencia") {
                    TextField("Consumo historico (km/gal)", text: $fuelEconomyReferenceKilometersPerGallon)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("vehicle.referenceKmPerGal")
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
            .alert("No se pudo guardar", isPresented: Binding(get: { saveError != nil }, set: { _ in saveError = nil })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
            .onAppear(perform: loadExistingData)
        }
    }

    private func save() {
        guard let tankCapacityValue = tankCapacityGallons.asDecimalDouble,
              let referenceKmPerGallonValue = fuelEconomyReferenceKilometersPerGallon.asDecimalDouble else {
            saveError = "Completa la capacidad del tanque y el consumo historico con valores numericos."
            return
        }

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
        target.engine = engine.trimmed
        target.plate = plate.trimmed.uppercased()
        target.odometerUnit = odometerUnit
        target.tankCapacityGallons = tankCapacityValue
        target.fuelScaleMax = FuelLevelScale.normalize(fuelScaleMax, maxValue: 12, step: 1)
        target.fuelScaleStep = FuelLevelScale.normalize(fuelScaleStep, maxValue: 1, step: 0.25)
        target.fuelEconomyReferenceKilometersPerGallon = referenceKmPerGallonValue
        target.notes = notes.trimmed
        if vehicle == nil {
            modelContext.insert(target)
        }

        do {
            try SyncMetadataMaintainer.recordChange(ownerID: target.id, kind: "vehicle",
                                                    createdAt: target.createdAt, updatedAt: .now,
                                                    in: modelContext)
            try modelContext.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func loadExistingData() {
        name = vehicle?.name ?? ""
        make = vehicle?.make ?? ""
        modelName = vehicle?.modelName ?? ""
        year = vehicle.map { String($0.year) } ?? ""
        engine = vehicle?.engine ?? ""
        plate = vehicle?.plate ?? ""
        odometerUnit = vehicle?.odometerUnit ?? .miles
        tankCapacityGallons = vehicle.map { CartrackFormatters.decimal($0.tankCapacityGallons) } ?? "14"
        fuelScaleMax = vehicle?.fuelScaleMax ?? FuelLevelScale.defaultMax
        fuelScaleStep = vehicle?.fuelScaleStep ?? FuelLevelScale.defaultStep
        fuelEconomyReferenceKilometersPerGallon = vehicle.map { CartrackFormatters.decimal($0.fuelEconomyReferenceKilometersPerGallon) } ?? "24.5"
        notes = vehicle?.notes ?? ""
    }
}
