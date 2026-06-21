import SwiftData
import SwiftUI

struct CaptureHomeView: View {
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    var body: some View {
        Group {
            if vehicles.isEmpty {
                EmptyStateView(
                    title: "Primero crea un vehiculo",
                    message: "Necesitas al menos un vehiculo antes de registrar llenados o snapshots.",
                    systemImage: "car.side.fill"
                )
            } else {
                List {
                    Section("Nuevo registro") {
                        NavigationLink {
                            FillUpFormView()
                        } label: {
                            Label("Registrar llenado", systemImage: "fuelpump.fill")
                        }
                        .accessibilityIdentifier("capture.fillup")

                        NavigationLink {
                            SnapshotFormView()
                        } label: {
                            Label("Registrar snapshot", systemImage: "gauge.open.with.lines.needle.33percent")
                        }
                        .accessibilityIdentifier("capture.snapshot")
                    }

                    Section("Que se captura") {
                        Text("Llenado: factura, odometro y nivel de tanque.")
                        Text("Snapshot: odometro, nivel de tanque y opcionalmente trip.")
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Capturar")
    }
}
