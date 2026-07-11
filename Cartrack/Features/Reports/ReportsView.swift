import SwiftData
import SwiftUI
import UIKit

enum ReportsGranularity: String, CaseIterable, Identifiable {
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly:
            return "Semanal"
        case .monthly:
            return "Mensual"
        }
    }
}

struct ReportsView: View {
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \FuelFillEvent.date, order: .reverse) private var fillEvents: [FuelFillEvent]
    @Query(sort: \SnapshotEvent.date, order: .reverse) private var snapshotEvents: [SnapshotEvent]
    @Query(sort: \MonthlyManualAdjustment.monthStart, order: .reverse) private var adjustments: [MonthlyManualAdjustment]

    @State private var selectedVehicleID: UUID?
    @State private var selectedGranularity: ReportsGranularity = .weekly
    @AppStorage("reports.monthlyMode") private var monthlyModeRawValue = MonthlyAllocationMode.finalFillMonth.rawValue
    @State private var exportMessage: String?
    @State private var exportErrorMessage: String?
    @State private var lastCSVURL: URL?
    @State private var lastPDFURL: URL?

    private var monthlyMode: MonthlyAllocationMode {
        MonthlyAllocationMode(rawValue: monthlyModeRawValue) ?? .finalFillMonth
    }

    private var selectedVehicleName: String {
        vehicles.first(where: { $0.id == selectedVehicleID })?.displayName ?? "Todos los vehiculos"
    }

    private var weeklyReports: [DetailedWeeklyReport] {
        AnalyticsEngine.detailedWeeklyReports(
            fills: fillEvents,
            snapshots: snapshotEvents,
            vehicleID: selectedVehicleID
        )
    }

    private var monthlyReports: [DetailedMonthlyReport] {
        AnalyticsEngine.detailedMonthlyReports(
            fills: fillEvents,
            snapshots: snapshotEvents,
            adjustments: adjustments,
            vehicleID: selectedVehicleID,
            mode: monthlyMode
        )
    }

    private var tankComparisons: [TankComparisonReport] {
        AnalyticsEngine.tankComparisonReports(
            fills: fillEvents,
            vehicleID: selectedVehicleID
        )
    }

    private var currentPayload: ReportExportPayload {
        ReportExportPayload(
            vehicleName: selectedVehicleName,
            generatedAt: .now,
            granularity: selectedGranularity,
            weeklyReports: weeklyReports,
            monthlyReports: monthlyReports,
            tankComparisons: tankComparisons
        )
    }

    var body: some View {
        Group {
            if vehicles.isEmpty {
                EmptyStateView(
                    title: "Aun no hay reportes",
                    message: "Primero crea un vehiculo y guarda llenados o snapshots para generar reportes exportables.",
                    systemImage: "doc.text.magnifyingglass"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VehicleFilterPicker(vehicles: vehicles, selectedVehicleID: $selectedVehicleID)

                        Picker("Vista", selection: $selectedGranularity) {
                            ForEach(ReportsGranularity.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("reports.granularity")

                        if selectedGranularity == .monthly {
                            Picker("Asignacion mensual", selection: Binding(
                                get: { monthlyMode },
                                set: { monthlyModeRawValue = $0.rawValue }
                            )) {
                                ForEach(MonthlyAllocationMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("reports.monthlyMode")
                        }

                        exportActions
                        reportSummarySection
                        reportListSection
                        tankComparisonSection
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Reportes")
        .alert("No se pudo exportar", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
        .onAppear {
            if selectedVehicleID == nil {
                selectedVehicleID = vehicles.first?.id
            }
        }
    }

    private var exportActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exportacion")
                .font(.headline)

            HStack {
                Button("Exportar CSV") {
                    exportCSV()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("reports.export.csv")

                Button("Exportar PDF") {
                    exportPDF()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reports.export.pdf")
            }

            if let exportMessage {
                Text(exportMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reports.export.status")
            }

            if let lastCSVURL {
                ShareLink(item: lastCSVURL) {
                    Label("Compartir ultimo CSV", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("reports.share.csv")
            }

            if let lastPDFURL {
                ShareLink(item: lastPDFURL) {
                    Label("Compartir ultimo PDF", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("reports.share.pdf")
            }
        }
    }

    @ViewBuilder
    private var reportSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resumen")
                .font(.headline)

            switch selectedGranularity {
            case .weekly:
                if let report = weeklyReports.first {
                    HStack {
                        MetricCard(
                            title: "Semana actual",
                            primary: CartrackFormatters.decimal(report.distanceKilometers, suffix: "km"),
                            secondary: "\(CartrackFormatters.decimal(report.distanceMiles, suffix: "mi")) • \(report.valueOrigin.title)",
                            tint: .blue
                        )
                        MetricCard(
                            title: "Uso diario",
                            primary: CartrackFormatters.decimal(report.averageDailyKilometers, suffix: "km"),
                            secondary: "\(report.daysOfUse) dia(s) con actividad",
                            tint: .mint
                        )
                    }

                    MetricCard(
                        title: "Consumo semanal",
                        primary: report.kmPerGallon.map { CartrackFormatters.decimal($0, suffix: "km/gal") } ?? "N/A",
                        secondary: report.totalCost.map { "Costo: \(CartrackFormatters.currency($0))" } ?? "Costo no disponible",
                        tint: .orange
                    )
                } else {
                    emptyReportText("Todavia no hay datos suficientes para construir una semana reportable.")
                }
            case .monthly:
                if let report = monthlyReports.first {
                    MetricCard(
                        title: "Mes visible",
                        primary: CartrackFormatters.currency(report.totalPaid),
                        secondary: "\(CartrackFormatters.decimal(report.distanceKilometers, suffix: "km")) • \(report.consumptionOrigin.title)",
                        tint: .green
                    )

                    HStack {
                        MetricCard(
                            title: "Consumo",
                            primary: report.kmPerGallon.map { CartrackFormatters.decimal($0, suffix: "km/gal") } ?? "N/A",
                            secondary: report.gallonsConsumed.map { CartrackFormatters.decimal($0, suffix: "gal") } ?? "Galones no disponibles",
                            tint: .orange
                        )
                        MetricCard(
                            title: "Autonomia",
                            primary: report.averageAutonomyKilometers.map { CartrackFormatters.decimal($0, suffix: "km") } ?? "N/A",
                            secondary: report.estimatedConsumedCost.map { "Consumido: \(CartrackFormatters.currency($0))" } ?? "Sin estimacion",
                            tint: .teal
                        )
                    }
                } else {
                    emptyReportText("Aun no hay datos suficientes para construir un mes reportable.")
                }
            }
        }
    }

    @ViewBuilder
    private var reportListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedGranularity == .weekly ? "Detalle semanal" : "Detalle mensual")
                .font(.headline)

            switch selectedGranularity {
            case .weekly:
                if weeklyReports.isEmpty {
                    emptyReportText("No hay semanas para mostrar.")
                } else {
                    ForEach(weeklyReports.prefix(8)) { report in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(formattedWeek(report.weekStart))
                                .font(.subheadline.weight(.semibold))
                            Text("Distancia: \(CartrackFormatters.decimal(report.distanceKilometers, suffix: "km"))")
                            Text("Consumo: \(report.kmPerGallon.map { CartrackFormatters.decimal($0, suffix: "km/gal") } ?? "N/A")")
                            Text("Origen: \(report.valueOrigin.title) • Dias de uso: \(report.daysOfUse)")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            case .monthly:
                if monthlyReports.isEmpty {
                    emptyReportText("No hay meses para mostrar.")
                } else {
                    ForEach(monthlyReports.prefix(8)) { report in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(report.monthStart.formattedMonth())
                                .font(.subheadline.weight(.semibold))
                            Text("Pagado: \(CartrackFormatters.currency(report.totalPaid))")
                            Text("Distancia: \(CartrackFormatters.decimal(report.distanceKilometers, suffix: "km"))")
                            Text("Consumo: \(report.kmPerGallon.map { CartrackFormatters.decimal($0, suffix: "km/gal") } ?? "N/A")")
                            Text("Origen: \(report.consumptionOrigin.title) • Llenados: \(report.fillCount)")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
        .accessibilityIdentifier("reports.list")
    }

    @ViewBuilder
    private var tankComparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comparativo por tanque")
                .font(.headline)

            if tankComparisons.isEmpty {
                emptyReportText("Necesitas al menos dos llenados completos para comparar tanques cerrados.")
            } else {
                ForEach(tankComparisons.prefix(5)) { comparison in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(formattedDate(comparison.startDate)) - \(formattedDate(comparison.endDate))")
                            .font(.subheadline.weight(.semibold))
                        Text("Odometro: \(CartrackFormatters.decimal(comparison.openingOdometerKilometers, suffix: "km")) -> \(CartrackFormatters.decimal(comparison.closingOdometerKilometers, suffix: "km"))")
                        Text("Rendimiento: \(CartrackFormatters.decimal(comparison.kmPerGallon, suffix: "km/gal")) • Costo/km: \(CartrackFormatters.currency(comparison.costPerKilometer))")
                        if comparison.isBest || comparison.isWorst {
                            Text(comparison.isBest ? "Mejor tanque" : "Peor tanque")
                                .foregroundStyle(comparison.isBest ? .green : .orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    @ViewBuilder
    private func emptyReportText(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func exportCSV() {
        do {
            let url = try ReportExportService.exportCSV(payload: currentPayload)
            lastCSVURL = url
            exportMessage = "CSV listo: \(url.lastPathComponent)"
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func exportPDF() {
        do {
            let url = try ReportExportService.exportPDF(payload: currentPayload)
            lastPDFURL = url
            exportMessage = "PDF listo: \(url.lastPathComponent)"
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func formattedWeek(_ weekStart: Date) -> String {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(formattedDate(weekStart)) - \(formattedDate(end))"
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_GT")
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

struct ReportExportPayload {
    let vehicleName: String
    let generatedAt: Date
    let granularity: ReportsGranularity
    let weeklyReports: [DetailedWeeklyReport]
    let monthlyReports: [DetailedMonthlyReport]
    let tankComparisons: [TankComparisonReport]
}

enum ReportExportService {
    static func exportCSV(
        payload: ReportExportPayload,
        directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let url = directory.appendingPathComponent(fileName(prefix: "reporte", granularity: payload.granularity, ext: "csv"))
        let csv = buildCSV(payload: payload)
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func exportPDF(
        payload: ReportExportPayload,
        directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let url = directory.appendingPathComponent(fileName(prefix: "reporte", granularity: payload.granularity, ext: "pdf"))
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        try renderer.writePDF(to: url) { context in
            context.beginPage()
            var cursorY: CGFloat = 32
            let left: CGFloat = 28
            let usableWidth = pageRect.width - (left * 2)

            func draw(_ text: String, font: UIFont, color: UIColor = .label) {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color
                ]
                let rect = NSString(string: text).boundingRect(
                    with: CGSize(width: usableWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                if cursorY + rect.height > pageRect.height - 32 {
                    context.beginPage()
                    cursorY = 32
                }
                NSString(string: text).draw(
                    in: CGRect(x: left, y: cursorY, width: usableWidth, height: rect.height),
                    withAttributes: attributes
                )
                cursorY += rect.height + 10
            }

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es_GT")
            formatter.dateStyle = .medium
            formatter.timeStyle = .short

            draw("Cartrack - Reporte \(payload.granularity.title)", font: .boldSystemFont(ofSize: 22))
            draw("Vehiculo: \(payload.vehicleName)", font: .systemFont(ofSize: 14))
            draw("Generado: \(formatter.string(from: payload.generatedAt))", font: .systemFont(ofSize: 14))

            switch payload.granularity {
            case .weekly:
                draw("Resumen semanal", font: .boldSystemFont(ofSize: 18))
                if payload.weeklyReports.isEmpty {
                    draw("No hay semanas reportables.", font: .systemFont(ofSize: 13), color: .secondaryLabel)
                } else {
                    for report in payload.weeklyReports.prefix(10) {
                        draw(
                            "\(csvDate(report.weekStart)) | \(formatDecimal(report.distanceKilometers)) km | \(report.kmPerGallon.map { formatDecimal($0) } ?? "N/A") km/gal | \(report.valueOrigin.title)",
                            font: .systemFont(ofSize: 13)
                        )
                    }
                }
            case .monthly:
                draw("Resumen mensual", font: .boldSystemFont(ofSize: 18))
                if payload.monthlyReports.isEmpty {
                    draw("No hay meses reportables.", font: .systemFont(ofSize: 13), color: .secondaryLabel)
                } else {
                    for report in payload.monthlyReports.prefix(10) {
                        draw(
                            "\(csvDate(report.monthStart)) | Pagado \(CartrackFormatters.currency(report.totalPaid)) | \(formatDecimal(report.distanceKilometers)) km | \(report.consumptionOrigin.title)",
                            font: .systemFont(ofSize: 13)
                        )
                    }
                }
            }

            draw("Comparativo por tanque", font: .boldSystemFont(ofSize: 18))
            if payload.tankComparisons.isEmpty {
                draw("No hay tanques cerrados suficientes.", font: .systemFont(ofSize: 13), color: .secondaryLabel)
            } else {
                for comparison in payload.tankComparisons.prefix(10) {
                    let badge = comparison.isBest ? "Mejor" : comparison.isWorst ? "Peor" : "Normal"
                    draw(
                        "\(csvDate(comparison.startDate)) - \(csvDate(comparison.endDate)) | \(formatDecimal(comparison.distanceKilometers)) km | \(formatDecimal(comparison.kmPerGallon)) km/gal | \(badge)",
                        font: .systemFont(ofSize: 13)
                    )
                }
            }
        }

        return url
    }

    private static func buildCSV(payload: ReportExportPayload) -> String {
        var rows = [[String]]()
        rows.append(["reporte", payload.granularity.title])
        rows.append(["vehiculo", payload.vehicleName])
        rows.append(["generado", isoDateTime(payload.generatedAt)])
        rows.append([])

        switch payload.granularity {
        case .weekly:
            rows.append(contentsOf: AnalyticsEngine.weeklyReportCSVRows(payload.weeklyReports))
        case .monthly:
            rows.append(contentsOf: AnalyticsEngine.monthlyReportCSVRows(payload.monthlyReports))
        }

        rows.append([])
        rows.append(["comparativo_tanques"])
        rows.append(contentsOf: AnalyticsEngine.tankComparisonCSVRows(payload.tankComparisons))

        return rows
            .map { row in row.map(csvEscape).joined(separator: ",") }
            .joined(separator: "\n")
    }

    private static func fileName(
        prefix: String,
        granularity: ReportsGranularity,
        ext: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(prefix)-\(granularity.rawValue)-\(formatter.string(from: .now)).\(ext)"
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func isoDateTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    private static func csvDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func formatDecimal(_ value: Double) -> String {
        CartrackFormatters.decimal(value)
    }
}
