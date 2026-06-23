import SwiftData
import SwiftUI
import UIKit

private enum SnapshotWizardStep: Int {
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
            "Agrega las fotos del odometro y del nivel de tanque."
        case .review:
            "Revisa lo que el OCR pudo prellenar y ajusta el nivel de tanque."
        case .confirm:
            "Confirma el resumen antes de guardar el snapshot."
        }
    }
}

private enum SnapshotFocusedField: Hashable {
    case odometer
}

struct SnapshotFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \ImageAsset.createdAt, order: .reverse) private var imageAssets: [ImageAsset]

    private let ocrService = OCRService()
    @StateObject private var locationService = LocationService()

    let event: SnapshotEvent?

    @State private var selectedVehicleID: UUID?
    @State private var date = Date()
    @State private var odometerMiles = ""
    @State private var tripMiles = ""
    @State private var notes = ""
    @State private var fuelLevelRemaining = FuelLevelScale.defaultMax
    @State private var odometerOCRText = ""
    @State private var fuelLevelOCRText = ""

    @State private var odometerImage: UIImage?
    @State private var fuelLevelImage: UIImage?
    @State private var existingOdometerPath: String?
    @State private var existingFuelLevelPath: String?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var wizardStep: SnapshotWizardStep = .evidence
    @FocusState private var focusedField: SnapshotFocusedField?

    init(event: SnapshotEvent? = nil) {
        self.event = event
    }

    private var selectedVehicle: Vehicle? {
        vehicles.first(where: { $0.id == selectedVehicleID })
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    var body: some View {
        Form {
            wizardProgressSection
            wizardContent
        }
        .navigationTitle(event == nil ? "Nuevo snapshot" : "Editar snapshot")
        .toolbar {
            if wizardStep == .evidence {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isAnalyzing ? "Analizando..." : "Siguiente") {
                        Task { await continueFromEvidence() }
                    }
                    .disabled(isAnalyzing || selectedVehicle == nil)
                    .accessibilityIdentifier("snapshot.next")
                }
            } else if wizardStep == .review {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Siguiente") {
                        wizardStep = .confirm
                    }
                    .accessibilityIdentifier("snapshot.next")
                }
            } else if wizardStep == .confirm {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                        .accessibilityIdentifier("snapshot.save")
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
            .accessibilityIdentifier("snapshot.wizard.step")
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
                .accessibilityIdentifier("snapshot.next.inline")
            }
        case .review:
            readingSection
            fuelLevelReviewSection
            ocrSection
            Section {
                HStack {
                    Button("Atras") {
                        wizardStep = .evidence
                    }
                    .accessibilityIdentifier("snapshot.back")

                    Spacer()

                    Button("Siguiente") {
                        wizardStep = .confirm
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("snapshot.next.inline")
                }
            }
        case .confirm:
            confirmationSection
            Section {
                HStack {
                    Button("Atras") {
                        wizardStep = .review
                    }
                    .accessibilityIdentifier("snapshot.back")

                    Spacer()

                    Button("Guardar", action: save)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("snapshot.save.inline")
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
            .accessibilityIdentifier("snapshot.vehicle.picker")
        }
    }

    @ViewBuilder
    private var evidenceSections: some View {
        ImageCaptureField(
            title: "Odometro",
            caption: "Captura separada del odometro o cluster.",
            existingPath: $existingOdometerPath,
            image: $odometerImage
        )
        ImageCaptureField(
            title: "Nivel de tanque",
            caption: "Captura separada del nivel de combustible. Si es una aguja analogica, confirma los espacios manualmente en el siguiente paso.",
            existingPath: $existingFuelLevelPath,
            image: $fuelLevelImage
        )
    }

    private var readingSection: some View {
        Section("Lectura") {
            DatePicker("Fecha", selection: $date, displayedComponents: [.date, .hourAndMinute])
            TextField("Odometro en millas", text: $odometerMiles)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .odometer)
                .accessibilityIdentifier("snapshot.odometer")
            TextField("Trip en millas (opcional)", text: $tripMiles)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("snapshot.trip")
            TextField("Notas", text: $notes, axis: .vertical)
                .accessibilityIdentifier("snapshot.notes")
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
                accessibilityPrefix: "snapshot",
                value: $fuelLevelRemaining
            )
        }
    }

    private var ocrSection: some View {
        Section("OCR local") {
            Button(isAnalyzing ? "Analizando..." : "Analizar de nuevo") {
                Task { await analyzeImages() }
            }
            .disabled(isAnalyzing)
            .accessibilityIdentifier("snapshot.analyze")

            let ocrText = [odometerOCRText, fuelLevelOCRText]
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
            if odometerMiles.asDouble == nil {
                LabeledContent("Odometro", value: "Pendiente")
                Button("Completar odometro") {
                    moveToOdometerReview()
                }
                .accessibilityIdentifier("snapshot.completeOdometer")
            } else {
                LabeledContent("Odometro", value: display(odometerMiles, suffix: "mi"))
            }
            LabeledContent("Trip", value: display(tripMiles, suffix: "mi"))
            LabeledContent("Espacios restantes", value: CartrackFormatters.decimal(fuelLevelRemaining))
        }
    }

    @MainActor
    private func analyzeImages() async {
        guard let vehicle = selectedVehicle else { return }
        isAnalyzing = true
        let result = await ocrService.analyzeSnapshot(
            odometerImage: odometerImage,
            fuelLevelImage: fuelLevelImage,
            fuelScaleMax: vehicle.fuelScaleMax
        )
        odometerOCRText = result.odometerText
        fuelLevelOCRText = result.fuelLevelText
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
        guard let odometerMilesValue = odometerMiles.asDouble else {
            moveToOdometerReview()
            errorMessage = "Completa el odometro manualmente para guardar el snapshot."
            return
        }

        let snapshot = event ?? SnapshotEvent(vehicle: vehicle)
        snapshot.vehicle = vehicle
        snapshot.date = date
        snapshot.odometerMilesOriginal = odometerMilesValue
        snapshot.odometerKilometers = UnitConversion.milesToKilometers(odometerMilesValue)
        snapshot.tripMilesOriginal = tripMiles.asDouble
        snapshot.tripKilometers = tripMiles.asDouble.map(UnitConversion.milesToKilometers)
        snapshot.fuelLevelRemaining = FuelLevelScale.normalize(
            fuelLevelRemaining,
            maxValue: vehicle.fuelScaleMax,
            step: vehicle.fuelScaleStep
        )
        snapshot.notes = notes.trimmed
        snapshot.odometerOCRText = odometerOCRText
        snapshot.fuelLevelOCRText = fuelLevelOCRText
        let coordinate = EventLocationPolicy.resolvedCoordinate(
            currentLatitude: locationService.currentCoordinate?.latitude,
            currentLongitude: locationService.currentCoordinate?.longitude,
            existingLatitude: event?.latitude,
            existingLongitude: event?.longitude
        )
        snapshot.latitude = coordinate?.latitude
        snapshot.longitude = coordinate?.longitude
        snapshot.updatedAt = .now

        if event == nil {
            modelContext.insert(snapshot)
        }

        do {
            try EventImageSynchronizer.replaceAssets(
                for: snapshot,
                images: [
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
        notes = event?.notes ?? ""
        fuelLevelRemaining = event?.fuelLevelRemaining ?? FuelLevelScale.defaultMax
        odometerOCRText = event?.odometerOCRText ?? ""
        fuelLevelOCRText = event?.fuelLevelOCRText ?? ""
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
            $0.ownerType == .snapshot &&
            $0.kind == kind
        })?.localPath
    }

    private func removedKinds() -> Set<CaptureImageKind> {
        var removed: Set<CaptureImageKind> = []
        if event != nil && existingOdometerPath == nil { removed.insert(.odometer) }
        if event != nil && existingFuelLevelPath == nil { removed.insert(.fuelLevel) }
        return removed
    }

    private func moveToOdometerReview() {
        wizardStep = .review
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            focusedField = .odometer
        }
    }

    private func display(_ value: String, suffix: String = "") -> String {
        guard let parsed = value.asDouble else { return "Pendiente" }
        let formatted = CartrackFormatters.decimal(parsed)
        return "\(formatted)\(suffix.isEmpty ? "" : " \(suffix)")"
    }
}
