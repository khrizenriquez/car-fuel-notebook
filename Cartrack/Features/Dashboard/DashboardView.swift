import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \FuelFillEvent.date, order: .reverse) private var fillEvents: [FuelFillEvent]
    @Query(sort: \SnapshotEvent.date, order: .reverse) private var snapshotEvents: [SnapshotEvent]
    @Query(sort: \MonthlyManualAdjustment.monthStart, order: .reverse) private var adjustments: [MonthlyManualAdjustment]

    @State private var selectedVehicleID: UUID?
    @AppStorage("dashboard.monthlyMode") private var monthlyModeRawValue = MonthlyAllocationMode.finalFillMonth.rawValue
    @State private var isShowingAdjustment = false

    private var monthlyMode: MonthlyAllocationMode {
        MonthlyAllocationMode(rawValue: monthlyModeRawValue) ?? .finalFillMonth
    }

    private var scopedVehicle: Vehicle? {
        vehicles.first(where: { $0.id == selectedVehicleID })
    }

    private var summaries: [MonthlySummary] {
        AnalyticsEngine.monthlySummaries(
            fills: fillEvents,
            adjustments: adjustments,
            vehicleID: selectedVehicleID,
            mode: monthlyMode
        )
    }

    private var currentMonthStart: Date {
        Date().startOfMonth()
    }

    private var currentMonthSummary: MonthlySummary? {
        summaries.first(where: { Calendar.current.isDate($0.monthStart, equalTo: currentMonthStart, toGranularity: .month) })
    }

    private var currentMonthPurchases: MonthlyPurchaseSummary {
        AnalyticsEngine.monthlyPurchases(
            fills: fillEvents,
            vehicleID: selectedVehicleID,
            monthStart: currentMonthStart
        )
    }

    private var currentMonthCaptures: MonthlyCaptureSummary {
        AnalyticsEngine.monthlyCaptures(
            fills: fillEvents,
            snapshots: snapshotEvents,
            vehicleID: selectedVehicleID,
            monthStart: currentMonthStart
        )
    }

    private var selectedCurrentTankStatus: CurrentTankStatus? {
        guard let vehicleID = selectedVehicleID ?? vehicles.first?.id else { return nil }
        return AnalyticsEngine.currentTankStatus(
            fills: fillEvents,
            snapshots: snapshotEvents,
            vehicleID: vehicleID
        )
    }

    private var inProgressCurrentMonthDistance: Double {
        guard let status = selectedCurrentTankStatus,
              let latestFillDate = status.latestFill?.date,
              Calendar.current.isDate(latestFillDate, equalTo: currentMonthStart, toGranularity: .month)
        else { return 0 }
        return status.distanceKilometers
    }

    private var previousMonthSummary: MonthlySummary? {
        guard let current = currentMonthSummary else { return summaries.dropFirst().first }
        return summaries.first(where: { $0.monthStart < current.monthStart })
    }

    private var currentMonthProjection: MonthlyProjection? {
        AnalyticsEngine.monthlyProjection(from: currentMonthSummary)
    }

    var body: some View {
        Group {
            if vehicles.isEmpty {
                EmptyStateView(
                    title: "Agrega tu primer vehiculo",
                    message: "Crea el BMW o cualquier otro carro para empezar a registrar facturas, odometro y nivel de tanque.",
                    systemImage: "car.side.fill"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VehicleFilterPicker(vehicles: vehicles, selectedVehicleID: $selectedVehicleID)

                        Picker("Vista", selection: Binding(
                            get: { monthlyMode },
                            set: { monthlyModeRawValue = $0.rawValue }
                        )) {
                            ForEach(MonthlyAllocationMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        summarySection
                        currentTankSection
                        monthlyHistorySection
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Cartrack")
        .sheet(isPresented: $isShowingAdjustment) {
            if let vehicle = scopedVehicle ?? vehicles.first {
                MonthlyAdjustmentEditor(
                    vehicle: vehicle,
                    monthStart: Date().startOfMonth(),
                    existingAdjustment: adjustments.first(where: {
                        $0.vehicle?.id == vehicle.id && Calendar.current.isDate($0.monthStart, equalTo: Date().startOfMonth(), toGranularity: .month)
                    })
                )
            }
        }
        .onAppear {
            if selectedVehicleID == nil {
                selectedVehicleID = vehicles.first?.id
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mes actual")
                .font(.headline)

            let spend = currentMonthPurchases.spend > 0 ? currentMonthPurchases.spend : currentMonthSummary?.spend ?? 0
            let snapshotOnlyDistance = inProgressCurrentMonthDistance > 0 ? 0 : currentMonthCaptures.latestSnapshotTripKilometers ?? 0
            let km = (currentMonthSummary?.totalDistanceKilometers ?? 0) + inProgressCurrentMonthDistance + snapshotOnlyDistance
            let kmPerGallon = currentMonthSummary?.kmPerGallon ?? 0
            let delta = monthOverMonthDelta()
            let spendSecondary = currentMonthPurchases.fillCount > 0
                ? "\(currentMonthPurchases.fillCount) llenado\(currentMonthPurchases.fillCount == 1 ? "" : "s") • \(CartrackFormatters.decimal(currentMonthPurchases.gallons, suffix: "gal comprados"))"
                : currentMonthCaptures.totalCaptureCount > 0
                    ? "\(currentMonthCaptures.snapshotCount) snapshot\(currentMonthCaptures.snapshotCount == 1 ? "" : "s") este mes"
                    : delta.map { "Cambio vs mes anterior: \($0)" } ?? "Sin comparacion todavia"
            let distanceSecondary = distanceSecondaryText(snapshotOnlyDistance: snapshotOnlyDistance)

            MetricCard(
                title: "Gasto",
                primary: CartrackFormatters.currency(spend),
                secondary: spendSecondary,
                tint: .green
            )

            HStack {
                MetricCard(
                    title: "Distancia",
                    primary: CartrackFormatters.decimal(km, suffix: "km"),
                    secondary: distanceSecondary,
                    tint: .blue
                )
                .accessibilityIdentifier("dashboard.distance")
                MetricCard(
                    title: "Rendimiento",
                    primary: CartrackFormatters.decimal(kmPerGallon, suffix: "km/gal"),
                    secondary: "Costo/km: \(CartrackFormatters.currency(currentMonthSummary?.costPerKilometer ?? 0))",
                    tint: .orange
                )
            }

            MetricCard(
                title: "Capturas",
                primary: "\(currentMonthCaptures.totalCaptureCount)",
                secondary: captureSummaryText(),
                tint: .mint
            )
            .accessibilityIdentifier("dashboard.captures")

            if let projection = currentMonthProjection {
                MetricCard(
                    title: "Proyeccion de cierre",
                    primary: CartrackFormatters.currency(projection.projectedSpend),
                    secondary: "Dia \(projection.elapsedDays)/\(projection.totalDays) • \(CartrackFormatters.decimal(projection.projectedDistanceKilometers, suffix: "km")) estimados",
                    tint: .indigo
                )
                .accessibilityIdentifier("dashboard.projection")
            }

            Button("Ajustar millas manuales del mes") {
                isShowingAdjustment = true
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("dashboard.adjustment.open")
        }
    }

    private var currentTankSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tanque actual")
                .font(.headline)

            if let vehicleID = selectedVehicleID ?? vehicles.first?.id {
                let status = selectedCurrentTankStatus ?? AnalyticsEngine.currentTankStatus(fills: fillEvents, snapshots: snapshotEvents, vehicleID: vehicleID)

                HStack {
                    MetricCard(
                        title: status.latestFill == nil ? "Ultima lectura" : "Desde ultimo llenado",
                        primary: currentTankPrimary(status),
                        secondary: currentTankSecondary(status),
                        tint: .purple
                    )
                    MetricCard(
                        title: "Nivel restante",
                        primary: status.spacesRemaining.map { CartrackFormatters.decimal($0, suffix: "espacios") } ?? "N/A",
                        secondary: status.estimatedAutonomyKilometers.map { "Autonomia: \(CartrackFormatters.decimal($0, suffix: "km"))" } ?? "Aun no hay suficiente historial",
                        tint: .teal
                    )
                }

                if let estimatedCost = status.estimatedFuelCostConsumed {
                    Text("Costo estimado consumido en el tanque actual: \(CartrackFormatters.currency(estimatedCost))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Selecciona un vehiculo para ver su tanque actual.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var monthlyHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Historico mensual")
                .font(.headline)

            if summaries.isEmpty {
                Text("Aun no hay ciclos de tanque cerrados. Guarda al menos dos llenados para calcular rendimiento historico; mientras tanto, el gasto del mes y la ultima lectura se muestran arriba.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(summaries.prefix(6)) { summary in
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.monthStart.formattedMonth())
                        .font(.subheadline.weight(.semibold))
                    Text("Gasto: \(CartrackFormatters.currency(summary.spend))")
                    Text("Distancia: \(CartrackFormatters.decimal(summary.totalDistanceKilometers, suffix: "km"))")
                    Text("Rendimiento: \(CartrackFormatters.decimal(summary.kmPerGallon, suffix: "km/gal"))")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.secondary.opacity(0.08))
                )
            }
        }
    }

    private func monthOverMonthDelta() -> String? {
        guard let currentMonthSummary, let previousMonthSummary, previousMonthSummary.spend > 0 else { return nil }
        let percent = ((currentMonthSummary.spend - previousMonthSummary.spend) / previousMonthSummary.spend) * 100
        return "\(CartrackFormatters.decimal(percent, suffix: "%"))"
    }

    private func distanceSecondaryText(snapshotOnlyDistance: Double) -> String {
        if inProgressCurrentMonthDistance > 0 {
            return "Incluye el tanque en curso"
        }
        if snapshotOnlyDistance > 0 {
            return "Distancia reportada por el ultimo snapshot"
        }
        if currentMonthCaptures.snapshotCount > 0 {
            return "Snapshot registrado sin trip util"
        }
        return "Incluye ajustes manuales del mes"
    }

    private func captureSummaryText() -> String {
        guard currentMonthCaptures.totalCaptureCount > 0 else {
            return "Sin capturas este mes"
        }

        let fillText = "\(currentMonthCaptures.fillCount) llenado\(currentMonthCaptures.fillCount == 1 ? "" : "s")"
        let snapshotText = "\(currentMonthCaptures.snapshotCount) snapshot\(currentMonthCaptures.snapshotCount == 1 ? "" : "s")"
        let dateText = currentMonthCaptures.latestCaptureDate.map {
            "ultima: \($0.formatted(date: .abbreviated, time: .shortened))"
        }

        return ([fillText, snapshotText] + [dateText].compactMap { $0 }).joined(separator: " • ")
    }

    private func currentTankPrimary(_ status: CurrentTankStatus) -> String {
        if status.latestFill == nil, let kilometers = status.latestReadingKilometers {
            return CartrackFormatters.decimal(kilometers, suffix: "km")
        }
        return CartrackFormatters.decimal(status.distanceKilometers, suffix: "km")
    }

    private func currentTankSecondary(_ status: CurrentTankStatus) -> String {
        guard let date = status.latestReadingDate else {
            return "Ultima lectura: N/A"
        }

        let formattedDate = date.formatted(date: .abbreviated, time: .omitted)
        guard let kilometers = status.latestReadingKilometers else {
            return "Ultima lectura: \(formattedDate)"
        }

        if status.latestFill == nil {
            return "Sin llenado base todavia • \(formattedDate)"
        }
        return "Ultima lectura: \(formattedDate) • \(CartrackFormatters.decimal(kilometers, suffix: "km"))"
    }
}
