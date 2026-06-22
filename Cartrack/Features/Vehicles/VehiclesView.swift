import SwiftData
import SwiftUI

struct VehiclesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    @State private var selectedVehicle: Vehicle?
    @State private var isShowingForm = false
    @State private var vehiclesPendingDeletion: [Vehicle] = []
    @State private var deletionError: String?

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
        .confirmationDialog(
            "Eliminar vehiculo?",
            isPresented: Binding(
                get: { !vehiclesPendingDeletion.isEmpty },
                set: { if !$0 { vehiclesPendingDeletion = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button(deleteConfirmationTitle, role: .destructive, action: deletePendingVehicles)
                .accessibilityIdentifier("vehicle.delete.confirm")
            Button("Cancelar", role: .cancel) {
                vehiclesPendingDeletion = []
            }
        } message: {
            Text("Se eliminaran el vehiculo, sus llenados, snapshots, ajustes mensuales e imagenes locales asociadas.")
        }
        .alert("No se pudo eliminar", isPresented: Binding(get: { deletionError != nil }, set: { _ in deletionError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deletionError ?? "")
        }
    }

    private var deleteConfirmationTitle: String {
        vehiclesPendingDeletion.count == 1 ? "Eliminar vehiculo" : "Eliminar vehiculos"
    }

    private func deleteVehicles(offsets: IndexSet) {
        vehiclesPendingDeletion = offsets
            .filter { vehicles.indices.contains($0) }
            .map { vehicles[$0] }
    }

    private func deletePendingVehicles() {
        let vehiclesToDelete = vehiclesPendingDeletion
        vehiclesPendingDeletion = []

        do {
            for vehicle in vehiclesToDelete {
                try EventDeletionService.delete(vehicle: vehicle, context: modelContext)
            }
        } catch {
            deletionError = error.localizedDescription
        }
    }
}
