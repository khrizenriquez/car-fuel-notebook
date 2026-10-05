import Charts
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
    @State private var isShowingReports = false

    private var monthlyMode: MonthlyAllocationMode {
        MonthlyAllocationMode(rawValue: monthlyModeRawValue) ?? .finalFillMonth
    }

    private var scopedVehicle: Vehicle? {
        vehicles.first(where: { $0.id == selectedVehicleID })
    }

    private var selectedDistanceUnit: OdometerUnit {
        (scopedVehicle ?? vehicles.first)?.odometerUnit ?? .kilometers
    }

    private var summaries: [MonthlySummary] {
        AnalyticsEngine.monthlySummaries(
            fills: fillEvents,
            adjustments: adjustments,
            vehicleID: selectedVehicleID,
            mode: monthlyMode
        )
    }

    private var weeklySummaries: [WeeklySummary] {
        AnalyticsEngine.weeklySummaries(
            fills: fillEvents,
            vehicleID: selectedVehicleID
        )
    }

    private var currentMonthStart: Date {
        Date().startOfMonth()
    }

    private var currentWeekStart: Date {
        Date().startOfWeek()
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

    private var scopedTankCycles: [TankCycle] {
        AnalyticsEngine.tankCycles(fills: fillEvents, vehicleID: selectedVehicleID ?? vehicles.first?.id)
    }

    private var scopedFuelReadings: [SnapshotEvent] {
        snapshotEvents
            .filter { selectedVehicleID == nil || $0.vehicle?.id == selectedVehicleID }
            .sorted { $0.odometerKilometers < $1.odometerKilometers }
    }

    private var selectedCalibration: FuelGaugeCalibration? {
        guard let vehicleID = selectedVehicleID ?? vehicles.first?.id else { return nil }
        return AnalyticsEngine.fuelGaugeCalibration(fills: fillEvents, snapshots: snapshotEvents, vehicleID: vehicleID)
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

    private var currentWeekSummary: WeeklySummary? {
        weeklySummaries.first(where: { Calendar.current.isDate($0.weekStart, equalTo: currentWeekStart, toGranularity: .weekOfYear) })
    }

    private var currentWeekPurchases: WeeklyPurchaseSummary {
        AnalyticsEngine.weeklyPurchases(
            fills: fillEvents,
            vehicleID: selectedVehicleID,
            weekStart: currentWeekStart
        )
    }

    private var latestFillPricePerGallon: Double? {
        fillEvents
            .filter { selectedVehicleID == nil || $0.vehicle?.id == selectedVehicleID }
            .max(by: { $0.date < $1.date })?
            .pricePerGallon
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
                        analyticsChartSection
                        weeklyHistorySection
                        monthlyHistorySection
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Cartrack")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingReports = true
                } label: {
                    Label("Reportes", systemImage: "doc.text")
                }
                .accessibilityIdentifier("dashboard.reports")
            }
        }
        .navigationDestination(isPresented: $isShowingReports) {
            ReportsView()
        }
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
                ? "\(currentMonthPurchases.fillCount) llenado\(currentMonthPurchases.fillCount == 1 ? "" : "s") • \(CartrackFormatters.gallons(currentMonthPurchases.gallons, suffix: "gal comprados"))"
                : currentMonthCaptures.totalCaptureCount > 0
                    ? "\(currentMonthCaptures.snapshotCount) snapshot\(currentMonthCaptures.snapshotCount == 1 ? "" : "s") este mes"
                    : delta.map { "Cambio vs mes anterior: \($0)" } ?? "Sin comparacion todavia"
            let distanceSecondary = distanceSecondaryText(distanceKilometers: km, snapshotOnlyDistance: snapshotOnlyDistance)

            MetricCard(
                title: "Gasto",
                primary: CartrackFormatters.currency(spend),
                secondary: spendSecondary,
                tint: .green
            )

            HStack {
                MetricCard(
                    title: "Semana combustible",
                    primary: CartrackFormatters.gallons(currentWeekPurchases.gallons),
                    secondary: fuelPurchaseSecondary(
                        spend: currentWeekPurchases.spend,
                        averagePricePerGallon: currentWeekPurchases.averagePricePerGallon,
                        litersPerKilometer: currentWeekPurchases.litersPerKilometer(using: currentWeekSummary?.distanceKilometers ?? 0)
                    ),
                    tint: .pink
                )
                .accessibilityIdentifier("dashboard.weeklyFuel")

                MetricCard(
                    title: "Mes combustible",
                    primary: CartrackFormatters.gallons(currentMonthPurchases.gallons),
                    secondary: fuelPurchaseSecondary(
                        spend: currentMonthPurchases.spend,
                        averagePricePerGallon: currentMonthPurchases.averagePricePerGallon,
                        litersPerKilometer: currentMonthPurchases.litersPerKilometer(using: currentMonthSummary?.totalDistanceKilometers ?? 0)
                    ),
                    tint: .red
                )
                .accessibilityIdentifier("dashboard.monthlyFuel")
            }

            HStack {
                MetricCard(
                    title: "Distancia",
                    primary: km > 0 ? CartrackFormatters.distancePrimary(km, unit: selectedDistanceUnit) : "Pendiente",
                    secondary: distanceSecondary,
                    tint: .blue
                )
                .accessibilityIdentifier("dashboard.distance")
                MetricCard(
                    title: "Rendimiento",
                    primary: currentMonthSummary == nil ? "Pendiente" : CartrackFormatters.decimal(kmPerGallon, suffix: "km/gal"),
                    secondary: performanceSecondary(
                        litersPerKilometer: currentMonthPurchases.litersPerKilometer(using: currentMonthSummary?.totalDistanceKilometers ?? 0),
                        costPerKilometer: currentMonthSummary?.costPerKilometer,
                        latestPricePerGallon: latestFillPricePerGallon
                    ),
                    tint: .orange
                )
                .accessibilityIdentifier("dashboard.performance")
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

                if let insight = status.insight {
                    currentTankInsightView(insight)
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
                Text("Aun no hay ciclos de tanque cerrados. Guarda al menos dos llenados marcados como tanque lleno para calcular rendimiento historico; mientras tanto, el gasto del mes y la ultima lectura se muestran arriba.")
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

    private var analyticsChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tendencias")
                .font(.headline)

            if scopedTankCycles.isEmpty {
                ContentUnavailableView(
                    "Aún no hay tendencia",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Los gráficos aparecen tras dos llenados completos del mismo vehículo."))
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("dashboard.analytics.empty")
            } else {
                Chart(scopedTankCycles.suffix(8)) { cycle in
                    LineMark(
                        x: .value("Fecha", cycle.endDate),
                        y: .value("Rendimiento", cycle.kmPerGallon)
                    )
                    .foregroundStyle(.orange)
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Fecha", cycle.endDate),
                        y: .value("Rendimiento", cycle.kmPerGallon)
                    )
                    .foregroundStyle(.orange)
                }
                .chartYAxisLabel("km/gal")
                .frame(height: 150)
                .accessibilityLabel("Tendencia de rendimiento por tanque")
                .accessibilityIdentifier("dashboard.analytics.efficiency")

                if scopedFuelReadings.count >= 2 {
                    Chart(scopedFuelReadings) { reading in
                        LineMark(
                            x: .value("Distancia", reading.odometerKilometers),
                            y: .value("Nivel", reading.fuelLevelRemaining)
                        )
                        .foregroundStyle(.teal)
                        PointMark(
                            x: .value("Distancia", reading.odometerKilometers),
                            y: .value("Nivel", reading.fuelLevelRemaining)
                        )
                        .foregroundStyle(.teal)
                    }
                    .chartYAxisLabel("Nivel")
                    .chartXAxisLabel("Odómetro (km)")
                    .frame(height: 150)
                    .accessibilityLabel("Curva observada de combustible contra distancia")
                    .accessibilityIdentifier("dashboard.analytics.fuelCurve")
                }

                if let selectedCalibration {
                    Text(calibrationCopy(selectedCalibration))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("dashboard.analytics.calibration")
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.08)))
    }

    private var weeklyHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Historico semanal")
                .font(.headline)

            if weeklySummaries.isEmpty {
                Text("Aun no hay semanas con tanques cerrados para reportar. Los reportes semanales apareceran cuando existan cierres completos.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(weeklySummaries.prefix(6)) { summary in
                VStack(alignment: .leading, spacing: 6) {
                    Text(weekRangeText(for: summary.weekStart))
                        .font(.subheadline.weight(.semibold))
                    Text("Gasto: \(CartrackFormatters.currency(summary.spend))")
                    Text("Distancia: \(CartrackFormatters.decimal(summary.distanceKilometers, suffix: "km"))")
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

    private func distanceSecondaryText(distanceKilometers: Double, snapshotOnlyDistance: Double) -> String {
        let equivalent = distanceKilometers > 0
            ? "\(CartrackFormatters.distanceSecondary(distanceKilometers, unit: selectedDistanceUnit)) • "
            : ""
        if inProgressCurrentMonthDistance > 0 {
            return "\(equivalent)Incluye el tanque en curso"
        }
        if snapshotOnlyDistance > 0 {
            return "\(equivalent)Distancia reportada por el ultimo snapshot"
        }
        if currentMonthCaptures.snapshotCount > 0 {
            return "Snapshot registrado sin trip util"
        }
        if distanceKilometers > 0 {
            return "\(equivalent)Incluye ajustes manuales del mes"
        }
        return "Se calculara con trip o diferencia de odometro"
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

    private func fuelPurchaseSecondary(
        spend: Double,
        averagePricePerGallon: Double?,
        litersPerKilometer: Double?
    ) -> String {
        let priceText = averagePricePerGallon.map { "Promedio: \(CartrackFormatters.currency($0))/gal" } ?? "Promedio: N/A"
        let litersText = litersPerKilometer.map { "L/km: \(CartrackFormatters.decimal($0))" } ?? "L/km: N/A"
        return "\(CartrackFormatters.currency(spend)) • \(priceText) • \(litersText)"
    }

    private func performanceSecondary(
        litersPerKilometer: Double?,
        costPerKilometer: Double?,
        latestPricePerGallon: Double?
    ) -> String {
        let litersText = litersPerKilometer.map { "L/km: \(CartrackFormatters.decimal($0))" } ?? "L/km: N/A"
        let costText = costPerKilometer.map { "Costo/km: \(CartrackFormatters.currency($0))" } ?? "Costo/km: N/A"
        let priceText = latestPricePerGallon.map { "Ultimo precio: \(CartrackFormatters.currency($0))/gal" } ?? "Ultimo precio: N/A"
        return "\(litersText) • \(costText) • \(priceText)"
    }

    private func currentTankPrimary(_ status: CurrentTankStatus) -> String {
        if status.distanceKilometers > 0 {
            return CartrackFormatters.distancePrimary(status.distanceKilometers, unit: selectedDistanceUnit)
        }
        if status.latestFill == nil, status.latestReadingKilometers != nil {
            return "Pendiente"
        }
        return "Pendiente"
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
        return "Ultima lectura: \(formattedDate) • \(CartrackFormatters.distancePair(kilometers, unit: selectedDistanceUnit))"
    }

    private func currentTankInsightView(_ insight: CurrentTankInsight) -> some View {
        let copy = CurrentTankInsightFormatter.copy(
            for: insight,
            vehicleName: (scopedVehicle ?? vehicles.first)?.displayName
        )
        let comparison = copy.comparison
        let estimate = copy.estimate
        let accessibilitySummary = [copy.state, comparison, estimate]
            .compactMap { $0 }
            .joined(separator: "\n\n")

        return VStack(alignment: .leading, spacing: 12) {
            Label("Interpretacion del tanque", systemImage: "gauge.with.dots.needle.67percent")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Estado actual")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(copy.state)
                    .accessibilityIdentifier("dashboard.tankInsight.state")
            }

            if let comparison {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Comparacion con la medicion anterior")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(comparison)
                        .accessibilityIdentifier("dashboard.tankInsight.comparison")
                }
            }

            if let estimate {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Estimacion real")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(estimate)
                        .accessibilityIdentifier("dashboard.tankInsight.estimate")
                }
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.teal.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("dashboard.tankInsight")
    }

    private func weekRangeText(for weekStart: Date) -> String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(weekStart.formatted(date: .abbreviated, time: .omitted)) - \(end.formatted(date: .abbreviated, time: .omitted))"
    }

    private func calibrationCopy(_ calibration: FuelGaugeCalibration) -> String {
        switch calibration.sufficiency {
        case .sufficient:
            return "Curva del medidor calibrada con \(calibration.sampleCount) lecturas confirmadas."
        case .limited:
            return "Curva preliminar: \(calibration.sampleCount) lecturas; sigue registrando el nivel para estrechar la autonomía."
        case .insufficient:
            return "Aún no hay lecturas suficientes para calibrar la curva del medidor."
        }
    }
}
