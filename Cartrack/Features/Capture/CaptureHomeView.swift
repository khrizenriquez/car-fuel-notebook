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
                    title: AppCopy.text("Primero crea un vehículo", "Create a vehicle first"),
                    message: AppCopy.text("Necesitas al menos un vehículo antes de registrar llenados o registros de uso.", "You need at least one vehicle before logging fill-ups or usage snapshots."),
                    systemImage: "car.side.fill"
                )
            } else {
                List {
                    if !resumableSessions.isEmpty {
                        Section(AppCopy.text("Continuar captura", "Resume capture")) {
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
                                             ? AppCopy.text("Continuar llenado", "Resume fill-up") : AppCopy.text("Continuar registro de uso", "Resume usage snapshot"))
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
                    Section(AppCopy.text("Nuevo registro", "New record")) {
                        NavigationLink {
                            FillUpFormView()
                        } label: {
                            Label(AppCopy.text("Registrar llenado", "Log fill-up"), systemImage: "fuelpump.fill")
                        }
                        .accessibilityIdentifier("capture.fillup")

                        NavigationLink {
                            SnapshotFormView()
                        } label: {
                            Label(AppCopy.text("Registrar registro de uso", "Log usage snapshot"), systemImage: "gauge.open.with.lines.needle.33percent")
                        }
                        .accessibilityIdentifier("capture.snapshot")
                    }

                    Section(AppCopy.text("Qué se captura", "What is captured")) {
                        Text(AppCopy.text("Llenado: factura, odómetro y nivel de tanque.", "Fill-up: receipt, odometer, and fuel level."))
                        Text(AppCopy.text("Registro de uso: odómetro, nivel de tanque y trip opcional.", "Usage snapshot: odometer, fuel level, and optional trip."))
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(AppCopy.capture)
    }
}
