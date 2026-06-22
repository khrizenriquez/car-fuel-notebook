import SwiftData
import SwiftUI

private struct HistoryRowModel: Identifiable {
    let id: UUID
    let kind: HistoryEventKind
    let date: Date
    let title: String
    let subtitle: String
    let fillEvent: FuelFillEvent?
    let snapshotEvent: SnapshotEvent?
}

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \FuelFillEvent.date, order: .reverse) private var fillEvents: [FuelFillEvent]
    @Query(sort: \SnapshotEvent.date, order: .reverse) private var snapshotEvents: [SnapshotEvent]

    @State private var selectedVehicleID: UUID?
    @State private var rowsPendingDeletion: [HistoryRowModel] = []
    @State private var deletionError: String?

    private var rows: [HistoryRowModel] {
        let fills = fillEvents
            .filter { selectedVehicleID == nil || $0.vehicle?.id == selectedVehicleID }
            .map {
                HistoryRowModel(
                    id: $0.id,
                    kind: .fillUp,
                    date: $0.date,
                    title: $0.vehicle?.displayName ?? "Llenado",
                    subtitle: "\(CartrackFormatters.currency($0.totalCost)) • \(CartrackFormatters.decimal($0.gallons, suffix: "gal")) • \(CartrackFormatters.decimal($0.fuelLevelRemaining, suffix: "esp"))",
                    fillEvent: $0,
                    snapshotEvent: nil
                )
            }

        let snapshots = snapshotEvents
            .filter { selectedVehicleID == nil || $0.vehicle?.id == selectedVehicleID }
            .map {
                HistoryRowModel(
                    id: $0.id,
                    kind: .snapshot,
                    date: $0.date,
                    title: $0.vehicle?.displayName ?? "Snapshot",
                    subtitle: "\(CartrackFormatters.decimal($0.odometerKilometers, suffix: "km")) • \(CartrackFormatters.decimal($0.fuelLevelRemaining, suffix: "esp"))",
                    fillEvent: nil,
                    snapshotEvent: $0
                )
            }

        return (fills + snapshots).sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if vehicles.isEmpty {
                EmptyStateView(
                    title: "Sin vehiculos",
                    message: "Agrega un vehiculo para ver su historial.",
                    systemImage: "clock.badge.xmark"
                )
            } else {
                List {
                    Section {
                        VehicleFilterPicker(vehicles: vehicles, selectedVehicleID: $selectedVehicleID)
                    }

                    ForEach(rows) { row in
                        if let fill = row.fillEvent {
                            NavigationLink {
                                FillUpFormView(event: fill)
                            } label: {
                                rowLabel(row)
                            }
                            .accessibilityIdentifier("history.fillup.row")
                        } else if let snapshot = row.snapshotEvent {
                            NavigationLink {
                                SnapshotFormView(event: snapshot)
                            } label: {
                                rowLabel(row)
                            }
                            .accessibilityIdentifier("history.snapshot.row")
                        }
                    }
                    .onDelete(perform: deleteRows)
                }
            }
        }
        .navigationTitle("Historial")
        .confirmationDialog(
            "Eliminar evento?",
            isPresented: Binding(
                get: { !rowsPendingDeletion.isEmpty },
                set: { if !$0 { rowsPendingDeletion = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button(deleteConfirmationTitle, role: .destructive, action: deletePendingRows)
                .accessibilityIdentifier("history.delete.confirm")
            Button("Cancelar", role: .cancel) {
                rowsPendingDeletion = []
            }
        } message: {
            Text("Se eliminara el registro seleccionado y sus imagenes locales asociadas.")
        }
        .alert("No se pudo eliminar", isPresented: Binding(get: { deletionError != nil }, set: { _ in deletionError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deletionError ?? "")
        }
    }

    private func rowLabel(_ row: HistoryRowModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.kind == .fillUp ? "Llenado" : "Snapshot")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((row.kind == .fillUp ? Color.green : Color.blue).opacity(0.15))
                    .clipShape(Capsule())
                Text(row.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(row.title)
                .font(.subheadline.weight(.semibold))
            Text(row.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var deleteConfirmationTitle: String {
        rowsPendingDeletion.count == 1 ? "Eliminar evento" : "Eliminar eventos"
    }

    private func deleteRows(at offsets: IndexSet) {
        rowsPendingDeletion = offsets
            .filter { rows.indices.contains($0) }
            .map { rows[$0] }
    }

    private func deletePendingRows() {
        let rowsToDelete = rowsPendingDeletion
        rowsPendingDeletion = []

        do {
            for row in rowsToDelete {
                try delete(row)
            }
        } catch {
            deletionError = error.localizedDescription
        }
    }

    private func delete(_ row: HistoryRowModel) throws {
        if let fill = row.fillEvent {
            try EventDeletionService.delete(fillEvent: fill, context: modelContext)
        } else if let snapshot = row.snapshotEvent {
            try EventDeletionService.delete(snapshotEvent: snapshot, context: modelContext)
        }
    }
}
