import CoreLocation
import SwiftData
import SwiftUI
import UIKit

private enum FillUpWizardStep: Int {
    case evidence = 1
    case review = 2
    case confirm = 3

    var title: String {
        switch self {
        case .evidence: "Evidencias"
        case .review: "Revision"
        case .confirm: "Confirmar"
        }
    }

    var subtitle: String {
        switch self {
        case .evidence:
            "Agrega las fotos de factura, odometro y nivel de tanque."
        case .review:
            "Revisa lo que el OCR pudo prellenar y corrige cualquier valor."
        case .confirm:
            "Confirma el resumen antes de guardar el llenado."
        }
    }
}

struct FillUpFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \ImageAsset.createdAt, order: .reverse) private var imageAssets: [ImageAsset]

    private let ocrService = OCRService()
    @StateObject private var locationService = LocationService()

    let event: FuelFillEvent?

    @State private var selectedVehicleID: UUID?
    @State private var date = Date()
    @State private var odometerMiles = ""
    @State private var tripMiles = ""
    @State private var gallons = ""
    @State private var pricePerGallon = ""
    @State private var totalCost = ""
    @State private var stationName = ""
    @State private var notes = ""
    @State private var fuelLevelRemaining = FuelLevelScale.defaultMax
    @State private var invoiceOCRText = ""
    @State private var odometerOCRText = ""
    @State private var fuelLevelOCRText = ""

    @State private var invoiceImage: UIImage?
    @State private var odometerImage: UIImage?
    @State private var fuelLevelImage: UIImage?

    @State private var existingInvoicePath: String?
    @State private var existingOdometerPath: String?
    @State private var existingFuelLevelPath: String?

    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var wizardStep: FillUpWizardStep = .evidence

    init(event: FuelFillEvent? = nil) {
        self.event = event
    }

    private var selectedVehicle: Vehicle? {
        vehicles.first(where: { $0.id == selectedVehicleID })
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    private var tripWarning: String? {
        guard let trip = tripMiles.asDouble, trip > 5 else { return nil }
        return "El trip no parece estar cerca de 0 despues del llenado. Se guardara igual, pero revisalo."
    }

    var body: some View {
        Form {
            wizardProgressSection
            wizardContent
        }
        .navigationTitle(event == nil ? "Nuevo llenado" : "Editar llenado")
        .toolbar {
            if wizardStep == .evidence {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isAnalyzing ? "Analizando..." : "Siguiente") {
                        Task { await continueFromEvidence() }
                    }
                    .disabled(isAnalyzing || selectedVehicle == nil)
                    .accessibilityIdentifier("fill.next")
                }
            } else if wizardStep == .review {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Siguiente") {
                        wizardStep = .confirm
                    }
                    .accessibilityIdentifier("fill.next")
                }
            } else if wizardStep == .confirm {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                        .accessibilityIdentifier("fill.save")
                }
            }
        }
        .alert("No se pudo guardar", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            loadExistingData()
            if !isUITesting {
                await ReminderService.shared.requestAuthorization()
                locationService.requestAccessIfNeeded()
                locationService.refreshLocation()
            }
        }
    }

    private var wizardProgressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Paso \(wizardStep.rawValue) de 3: \(wizardStep.title)")
                    .font(.headline)
                Text(wizardStep.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("fill.wizard.step")
        }
    }

    @ViewBuilder
    private var wizardContent: some View {
        switch wizardStep {
        case .evidence:
            vehicleSection
            evidenceSections
            Section {
                Button(isAnalyzing ? "Analizando..." : "Siguiente") {
                    Task { await continueFromEvidence() }
                }
                .disabled(isAnalyzing || selectedVehicle == nil)
                .accessibilityIdentifier("fill.next.inline")
            }
        case .review:
            dataSection
            fuelLevelReviewSection
            tripWarningSection
            ocrSection
            Section {
                HStack {
                    Button("Atras") {
                        wizardStep = .evidence
                    }
                    .accessibilityIdentifier("fill.back")

                    Spacer()

                    Button("Siguiente") {
                        wizardStep = .confirm
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("fill.next.inline")
                }
            }
        case .confirm:
            confirmationSection
            tripWarningSection
            Section {
                HStack {
                    Button("Atras") {
                        wizardStep = .review
                    }
                    .accessibilityIdentifier("fill.back")

                    Spacer()

                    Button("Guardar", action: save)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("fill.save.inline")
                }
            }
        }
    }

    private var vehicleSection: some View {
        Section("Vehiculo") {
            Picker("Vehiculo", selection: $selectedVehicleID) {
                ForEach(vehicles, id: \.id) { vehicle in
                    Text(vehicle.displayName).tag(Optional(vehicle.id))
                }
            }
            .accessibilityIdentifier("fill.vehicle.picker")
        }
    }

    @ViewBuilder
    private var evidenceSections: some View {
        ImageCaptureField(
            title: "Factura",
            caption: "Factura del llenado para leer galones, precio y total.",
            existingPath: $existingInvoicePath,
            image: $invoiceImage
        )
        ImageCaptureField(
            title: "Odometro",
            caption: "Foto del odometro o cluster donde se vea el trip.",
            existingPath: $existingOdometerPath,
            image: $odometerImage
        )
        ImageCaptureField(
            title: "Nivel de tanque",
            caption: "Foto separada del nivel de combustible. Si es una aguja analogica, confirma los espacios manualmente en el siguiente paso.",
            existingPath: $existingFuelLevelPath,
            image: $fuelLevelImage
        )
    }

    private var dataSection: some View {
        Section("Datos") {
            DatePicker("Fecha", selection: $date, displayedComponents: [.date, .hourAndMinute])
            TextField("Odometro en millas", text: $odometerMiles)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("fill.odometer")
            TextField("Trip en millas", text: $tripMiles)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("fill.trip")
            TextField("Galones", text: $gallons)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("fill.gallons")
            TextField("Precio por galon", text: $pricePerGallon)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("fill.price")
            TextField("Total pagado", text: $totalCost)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("fill.total")
            TextField("Gasolinera o nota corta", text: $stationName)
                .accessibilityIdentifier("fill.station")
            TextField("Notas", text: $notes, axis: .vertical)
                .accessibilityIdentifier("fill.notes")
        }
    }

    private var fuelLevelReviewSection: some View {
        Section("Nivel de tanque") {
            Text("La foto del medidor queda guardada como evidencia. Para agujas analogicas, ajusta los espacios restantes manualmente.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            FuelLevelInputView(
                title: "Espacios restantes",
                maxValue: selectedVehicle?.fuelScaleMax ?? FuelLevelScale.defaultMax,
                step: selectedVehicle?.fuelScaleStep ?? FuelLevelScale.defaultStep,
                accessibilityPrefix: "fill",
                value: $fuelLevelRemaining
            )
        }
    }

    @ViewBuilder
    private var tripWarningSection: some View {
        if let tripWarning {
            Section("Revision") {
                Label(tripWarning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var ocrSection: some View {
        Section("OCR local") {
            Button(isAnalyzing ? "Analizando..." : "Analizar de nuevo") {
                Task { await analyzeImages() }
            }
            .disabled(isAnalyzing)
            .accessibilityIdentifier("fill.analyze")

            let ocrText = [invoiceOCRText, odometerOCRText, fuelLevelOCRText]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            if ocrText.isEmpty {
                Text("No hay texto OCR todavia o las fotos no contienen texto legible.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(ocrText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var confirmationSection: some View {
        Section("Resumen") {
            LabeledContent("Vehiculo", value: selectedVehicle?.displayName ?? "Pendiente")
            LabeledContent("Odometro", value: display(odometerMiles, suffix: "mi"))
            LabeledContent("Trip", value: display(tripMiles, suffix: "mi"))
            LabeledContent("Galones", value: display(gallons, suffix: "gal"))
            LabeledContent("Precio/galon", value: display(pricePerGallon, prefix: "Q"))
            LabeledContent("Total", value: display(totalCost, prefix: "Q"))
            Button("Editar montos de factura") {
                wizardStep = .review
            }
            .accessibilityIdentifier("fill.editInvoiceAmounts")
            LabeledContent("Espacios restantes", value: CartrackFormatters.decimal(fuelLevelRemaining))
            if !stationName.trimmed.isEmpty {
                LabeledContent("Gasolinera", value: stationName.trimmed)
            }
        }
    }

    @MainActor
    private func analyzeImages() async {
        guard let vehicle = selectedVehicle else { return }
        isAnalyzing = true
        let result = await ocrService.analyzeFillUp(
            invoiceImage: invoiceImage,
            odometerImage: odometerImage,
            fuelLevelImage: fuelLevelImage,
            fuelScaleMax: vehicle.fuelScaleMax
        )
        invoiceOCRText = result.invoiceText
        odometerOCRText = result.odometerText
        fuelLevelOCRText = result.fuelLevelText
        gallons = gallons.isEmpty ? result.gallons.map { String($0) } ?? gallons : gallons
        pricePerGallon = pricePerGallon.isEmpty ? result.pricePerGallon.map { String($0) } ?? pricePerGallon : pricePerGallon
        totalCost = totalCost.isEmpty ? result.totalCost.map { String($0) } ?? totalCost : totalCost
        odometerMiles = odometerMiles.isEmpty ? result.odometerMiles.map { String($0) } ?? odometerMiles : odometerMiles
        tripMiles = tripMiles.isEmpty ? result.tripMiles.map { String($0) } ?? tripMiles : tripMiles
        if let value = result.fuelLevelRemaining {
            fuelLevelRemaining = value
        }
        isAnalyzing = false
    }

    @MainActor
    private func continueFromEvidence() async {
        await analyzeImages()
        wizardStep = .review
    }

    private func save() {
        guard let vehicle = selectedVehicle else {
            errorMessage = "Selecciona un vehiculo."
            return
        }
        guard let odometerMilesValue = odometerMiles.asDouble,
              let gallonsValue = gallons.asDouble,
              let pricePerGallonValue = pricePerGallon.asDouble,
              let totalCostValue = totalCost.asDouble else {
            errorMessage = "Completa odometro, galones, precio y total con valores numericos."
            return
        }

        let fillEvent = event ?? FuelFillEvent(vehicle: vehicle)
        fillEvent.vehicle = vehicle
        fillEvent.date = date
        fillEvent.odometerMilesOriginal = odometerMilesValue
        fillEvent.odometerKilometers = UnitConversion.milesToKilometers(odometerMilesValue)
        fillEvent.tripMilesOriginal = tripMiles.asDouble
        fillEvent.tripKilometers = tripMiles.asDouble.map(UnitConversion.milesToKilometers)
        fillEvent.gallons = gallonsValue
        fillEvent.pricePerGallon = pricePerGallonValue
        fillEvent.totalCost = totalCostValue
        fillEvent.stationName = stationName.trimmed
        fillEvent.fuelLevelRemaining = FuelLevelScale.normalize(
            fuelLevelRemaining,
            maxValue: vehicle.fuelScaleMax,
            step: vehicle.fuelScaleStep
        )
        fillEvent.notes = notes.trimmed
        fillEvent.invoiceOCRText = invoiceOCRText
        fillEvent.odometerOCRText = odometerOCRText
        fillEvent.fuelLevelOCRText = fuelLevelOCRText
        let coordinate = EventLocationPolicy.resolvedCoordinate(
            currentLatitude: locationService.currentCoordinate?.latitude,
            currentLongitude: locationService.currentCoordinate?.longitude,
            existingLatitude: event?.latitude,
            existingLongitude: event?.longitude
        )
        fillEvent.latitude = coordinate?.latitude
        fillEvent.longitude = coordinate?.longitude
        fillEvent.updatedAt = .now

        if event == nil {
            modelContext.insert(fillEvent)
        }

        do {
            try EventImageSynchronizer.replaceAssets(
                for: fillEvent,
                images: [
                    .invoice: invoiceImage,
                    .odometer: odometerImage,
                    .fuelLevel: fuelLevelImage,
                ],
                removedKinds: removedKinds(),
                context: modelContext
            )
            try modelContext.save()
            Task {
                await ReminderService.shared.captureLogged()
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadExistingData() {
        selectedVehicleID = event?.vehicle?.id ?? vehicles.first?.id
        date = event?.date ?? .now
        odometerMiles = event?.odometerMilesOriginal.map { String($0) } ?? ""
        tripMiles = event?.tripMilesOriginal.map { String($0) } ?? ""
        gallons = event.map { String($0.gallons) } ?? ""
        pricePerGallon = event.map { String($0.pricePerGallon) } ?? ""
        totalCost = event.map { String($0.totalCost) } ?? ""
        stationName = event?.stationName ?? ""
        notes = event?.notes ?? ""
        fuelLevelRemaining = event?.fuelLevelRemaining ?? FuelLevelScale.defaultMax
        invoiceOCRText = event?.invoiceOCRText ?? ""
        odometerOCRText = event?.odometerOCRText ?? ""
        fuelLevelOCRText = event?.fuelLevelOCRText ?? ""
        existingInvoicePath = existingAssetPath(kind: .invoice)
        existingOdometerPath = existingAssetPath(kind: .odometer)
        existingFuelLevelPath = existingAssetPath(kind: .fuelLevel)
        if event != nil {
            wizardStep = .review
        }
    }

    private func existingAssetPath(kind: CaptureImageKind) -> String? {
        guard let event else { return nil }
        return imageAssets.first(where: {
            $0.eventID == event.id &&
            $0.ownerType == .fillUp &&
            $0.kind == kind
        })?.localPath
    }

    private func removedKinds() -> Set<CaptureImageKind> {
        var removed: Set<CaptureImageKind> = []
        if event != nil && existingInvoicePath == nil { removed.insert(.invoice) }
        if event != nil && existingOdometerPath == nil { removed.insert(.odometer) }
        if event != nil && existingFuelLevelPath == nil { removed.insert(.fuelLevel) }
        return removed
    }

    private func display(_ value: String, prefix: String = "", suffix: String = "") -> String {
        guard let parsed = value.asDouble else { return "Pendiente" }
        let formatted = CartrackFormatters.decimal(parsed)
        return "\(prefix)\(formatted)\(suffix.isEmpty ? "" : " \(suffix)")"
    }
}
