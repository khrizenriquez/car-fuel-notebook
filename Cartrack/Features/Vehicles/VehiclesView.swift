import SwiftData
import SwiftUI

struct VehiclesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    @State private var selectedVehicle: Vehicle?
    @State private var isShowingForm = false

    var body: some View {
        List {
            ForEach(vehicles, id: \.id) { vehicle in
                Button {
                    selectedVehicle = vehicle
                    isShowingForm = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vehicle.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Escala: 0 a \(CartrackFormatters.decimal(vehicle.fuelScaleMax)) en pasos de \(CartrackFormatters.decimal(vehicle.fuelScaleStep))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: deleteVehicles)
        }
        .navigationTitle("Vehiculos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    selectedVehicle = nil
                    isShowingForm = true
                } label: {
                    Label("Agregar", systemImage: "plus")
                }
                .accessibilityIdentifier("vehicle.add")
            }
        }
        .sheet(isPresented: $isShowingForm) {
            VehicleFormView(vehicle: selectedVehicle)
        }
    }

    private func deleteVehicles(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(vehicles[index])
        }
        try? modelContext.save()
    }
}
