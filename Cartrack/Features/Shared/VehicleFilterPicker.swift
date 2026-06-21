import SwiftUI

struct VehicleFilterPicker: View {
    let vehicles: [Vehicle]
    @Binding var selectedVehicleID: UUID?

    var body: some View {
        Picker("Vehiculo", selection: $selectedVehicleID) {
            Text("Todos").tag(Optional<UUID>.none)
            ForEach(vehicles, id: \.id) { vehicle in
                Text(vehicle.displayName).tag(Optional(vehicle.id))
            }
        }
        .pickerStyle(.menu)
    }
}
