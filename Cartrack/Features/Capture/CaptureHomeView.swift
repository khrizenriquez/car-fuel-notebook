import SwiftData
import SwiftUI

struct CaptureHomeView: View {
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \CaptureSessionRecord.updatedAt, order: .reverse)
    private var captureSessions: [CaptureSessionRecord]

    private var resumableSessions: [CaptureSessionRecord] {
        captureSessions.filter { row in
            guard let state = CaptureSessionState(rawValue: row.stateRawValue),
                  CaptureSessionKind(rawValue: row.kindRawValue) != nil else { return false }
            return state.isResumable
        }
    }

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
                    if !resumableSessions.isEmpty {
                        Section("Continuar captura") {
                            ForEach(resumableSessions, id: \.id) { row in
                                NavigationLink {
                                    if row.kindRawValue == CaptureSessionKind.fillUp.rawValue {
                                        FillUpFormView(resumeSessionID: row.id)
                                    } else {
                                        SnapshotFormView(resumeSessionID: row.id)
                                    }
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(row.kindRawValue == CaptureSessionKind.fillUp.rawValue
                                             ? "Continuar llenado" : "Continuar registro de uso")
                                        if let vehicle = vehicles.first(where: { $0.id == row.vehicleID }) {
                                            Text(vehicle.displayName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .accessibilityIdentifier("capture.resume.\(row.id.uuidString)")
                            }
                        }
                    }
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
