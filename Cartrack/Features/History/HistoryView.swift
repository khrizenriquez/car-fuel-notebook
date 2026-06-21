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

    private func deleteRows(at offsets: IndexSet) {
        for index in offsets {
            let row = rows[index]
            if let fill = row.fillEvent {
                try? EventDeletionService.delete(fillEvent: fill, context: modelContext)
            } else if let snapshot = row.snapshotEvent {
                try? EventDeletionService.delete(snapshotEvent: snapshot, context: modelContext)
            }
        }
    }
}
