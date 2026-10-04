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
    @Query(sort: \SnapshotEvent.date, order: .reverse) private var snapshotEvents: [SnapshotEvent]
    @Query(sort: \FuelFillEvent.date, order: .reverse) private var fillEvents: [FuelFillEvent]

    private let ocrService = OCRService()
    @StateObject private var locationService = LocationService()

    let event: FuelFillEvent?
    let resumeSessionID: UUID?

    @State private var selectedVehicleID: UUID?
    @State private var date = Date()
    @State private var odometerMiles = ""
    @State private var tripMiles = ""
    @State private var gallons = ""
    @State private var pricePerGallon = ""
    @State private var totalCost = ""
    @State private var isFullTank = true
    @State private var stationName = ""
    @State private var notes = ""
    @State private var odometerOverrideReason = ""
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
    @State private var captureSessionID: UUID?
    @State private var captureSessionRevision: Int64?
    @State private var captureDraft: CaptureDraft?
    @State private var captureFieldResults: [FieldResult] = []
    @State private var captureImageIssues: [CaptureImageKind: [CaptureImageIssue]] = [:]
    @State private var fuelLevelReviewed = false
    @State private var draftAutosaveTask: Task<Void, Never>?
    @State private var isSaving = false

    init(event: FuelFillEvent? = nil, resumeSessionID: UUID? = nil) {
        self.event = event
        self.resumeSessionID = resumeSessionID
    }

    private var selectedVehicle: Vehicle? {
        vehicles.first(where: { $0.id == selectedVehicleID })
    }

    private var odometerUnit: OdometerUnit {
        selectedVehicle?.odometerUnit ?? .miles
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
                        .disabled(isSaving)
                        .accessibilityIdentifier("fill.save")
                }
            }
        }
        .alert("No se pudo completar", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            loadExistingData()
            if let resumeSessionID, event == nil {
                await resumeCaptureSession(resumeSessionID)
            }
            if !isUITesting {
                await ReminderService.shared.requestAuthorization()
                locationService.requestAccessIfNeeded()
                locationService.refreshLocation()
            }
        }
        .onChange(of: draftSignature) { _, _ in scheduleDraftAutosave() }
        .onDisappear { scheduleDraftAutosave(immediate: true) }
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
            CaptureConfidenceSection(fields: captureFieldResults,
                                     imageIssues: captureImageIssues,
                                     isManuallyResolved: manuallyResolved,
                                     retake: { _ in wizardStep = .evidence })
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
                        .disabled(isSaving)
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
            accessibilityPrefix: "fill.invoiceImage",
            existingPath: $existingInvoicePath,
            image: $invoiceImage
        )
        ImageCaptureField(
            title: "Odometro",
            caption: "Foto del odometro o cluster donde se vea el trip.",
            accessibilityPrefix: "fill.odometerImage",
            existingPath: $existingOdometerPath,
            image: $odometerImage
        )
        ImageCaptureField(
            title: "Nivel de tanque",
            caption: "Foto separada del nivel de combustible. Si es una aguja analogica, confirma los espacios manualmente en el siguiente paso.",
            accessibilityPrefix: "fill.fuelImage",
            existingPath: $existingFuelLevelPath,
            image: $fuelLevelImage
        )
    }

    private var dataSection: some View {
        Section("Datos") {
            DatePicker("Fecha", selection: $date, displayedComponents: [.date, .hourAndMinute])
            TextField("Odometro en \(odometerUnit.inputLabel)", text: $odometerMiles)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("fill.odometer")
            TextField("Trip en \(odometerUnit.inputLabel)", text: $tripMiles)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("fill.trip")
            TextField("Motivo de corrección del odómetro (solo si retrocede)", text: $odometerOverrideReason, axis: .vertical)
                .accessibilityIdentifier("fill.odometerOverrideReason")
            TextField("Galones", text: $gallons)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("fill.gallons")
            TextField("Precio por galon", text: $pricePerGallon)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("fill.price")
            TextField("Total pagado", text: $totalCost)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("fill.total")
            Toggle("Tanque lleno", isOn: $isFullTank)
                .accessibilityIdentifier("fill.fullTank")
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
            if needsFuelLevelConfirmation {
                Toggle("Confirmé visualmente el nivel del medidor", isOn: $fuelLevelReviewed)
                    .accessibilityIdentifier("fill.fuelLevel.confirmed")
            }
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
            LabeledContent("Odometro", value: display(odometerMiles, suffix: odometerUnit.rawValue))
            LabeledContent("Trip", value: display(tripMiles, suffix: odometerUnit.rawValue))
            LabeledContent("Galones", value: displayDecimal(gallons, suffix: "gal", formatter: CartrackFormatters.gallons))
            LabeledContent("Precio/galon", value: displayDecimal(pricePerGallon, prefix: "Q"))
            LabeledContent("Total", value: displayDecimal(totalCost, prefix: "Q"))
            LabeledContent("Cierre de tanque", value: isFullTank ? "Tanque lleno" : "Carga parcial")
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
    private func analyzeImages(persistCurrentValues: Bool = true) async -> Bool {
        guard let vehicle = selectedVehicle else { return false }
        isAnalyzing = true
        defer { isAnalyzing = false }
        if event == nil {
            do {
                if persistCurrentValues, captureSessionID != nil {
                    draftAutosaveTask?.cancel()
                    guard await persistCurrentDraft() else { return false }
                }
                let workflow = FuelCaptureWorkflow(container: modelContext.container)
                let outcome = try await workflow.analyze(
                    input: fuelCaptureInput(for: vehicle), sessionID: captureSessionID
                )
                captureSessionID = outcome.session.id
                captureSessionRevision = outcome.session.revision
                captureDraft = outcome.session.draft
                invoiceImage = outcome.images[.invoice]
                odometerImage = outcome.images[.odometer]
                fuelLevelImage = outcome.images[.fuelLevel]
                if needsFuelLevelConfirmation { fuelLevelReviewed = false }
                captureFieldResults = outcome.fields
                captureImageIssues = outcome.imageIssues
                invoiceOCRText = outcome.recognizedText.invoiceText
                odometerOCRText = outcome.recognizedText.odometerText
                fuelLevelOCRText = outcome.recognizedText.fuelLevelText
                applyCaptureDraft(outcome.session.draft)
                return true
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        }
        let result = await ocrService.analyzeFillUp(
            invoiceImage: invoiceImage,
            odometerImage: odometerImage,
            fuelLevelImage: fuelLevelImage,
            fuelScaleMax: vehicle.fuelScaleMax,
            previousClusterReading: previousClusterReading(for: vehicle)
        )
        invoiceOCRText = result.invoiceText
        odometerOCRText = result.odometerText
        fuelLevelOCRText = result.fuelLevelText
        gallons = gallons.isEmpty ? result.gallons.map { String($0) } ?? gallons : gallons
        pricePerGallon = pricePerGallon.isEmpty ? result.pricePerGallon.map { String($0) } ?? pricePerGallon : pricePerGallon
        totalCost = totalCost.isEmpty ? result.totalCost.map { String($0) } ?? totalCost : totalCost
        odometerMiles = odometerMiles.isEmpty ? result.odometerMiles.map(formatOCRDistanceInput) ?? odometerMiles : odometerMiles
        tripMiles = tripMiles.isEmpty ? result.tripMiles.map(formatOCRDistanceInput) ?? tripMiles : tripMiles
        if let value = result.fuelLevelRemaining {
            fuelLevelRemaining = value
        }
        return true
    }

    private func fuelCaptureInput(for vehicle: Vehicle) -> FuelCaptureInput {
        var images: [CaptureImageKind: UIImage] = [:]
        if let invoiceImage { images[.invoice] = invoiceImage }
        if let odometerImage { images[.odometer] = odometerImage }
        if let fuelLevelImage { images[.fuelLevel] = fuelLevelImage }
        let previousSnapshot = snapshotEvents
            .filter { $0.vehicle?.id == vehicle.id && $0.date < date }
            .max(by: { $0.date < $1.date })
        let previousFill = fillEvents
            .filter { $0.vehicle?.id == vehicle.id && $0.date < date }
            .max(by: { $0.date < $1.date })
        let previousOdometer = [previousSnapshot.map { ($0.date, $0.odometerKilometers) },
                                previousFill.map { ($0.date, $0.odometerKilometers) }]
            .compactMap { $0 }
            .max(by: { $0.0 < $1.0 })?.1
        return FuelCaptureInput(
            vehicleID: vehicle.id, occurredAt: date, odometerUnit: vehicle.odometerUnit,
            tankCapacityGallons: Decimal(string: String(vehicle.tankCapacityGallons)) ?? 14,
            fuelScaleMax: Decimal(string: String(vehicle.fuelScaleMax)) ?? 8,
            fuelScaleStep: Decimal(string: String(vehicle.fuelScaleStep)) ?? 0.25,
            previousOdometerKilometers: previousOdometer.flatMap { Decimal(string: String($0)) },
            lastFillOdometerKilometers: previousFill.flatMap { Decimal(string: String($0.odometerKilometers)) },
            previousClusterReading: previousClusterReading(for: vehicle), images: images
        )
    }

    private func applyCaptureDraft(_ draft: CaptureDraft) {
        odometerOverrideReason = draft.odometerOverrideReason ?? ""
        func text(_ value: Decimal?) -> String? { value.map { NSDecimalNumber(decimal: $0).stringValue } }
        if odometerMiles.isEmpty || !draft.isManuallyEdited(.odometerKilometers) {
            odometerMiles = draft.odometerKilometers.map {
                formatOCRDistanceInput(UnitConversion.kilometersToMiles(NSDecimalNumber(decimal: $0).doubleValue))
            } ?? ""
        }
        if tripMiles.isEmpty || !draft.isManuallyEdited(.tripKilometers) {
            tripMiles = draft.tripKilometers.map {
                formatOCRDistanceInput(UnitConversion.kilometersToMiles(NSDecimalNumber(decimal: $0).doubleValue))
            } ?? ""
        }
        if gallons.isEmpty || !draft.isManuallyEdited(.volumeGallons) { gallons = text(draft.volumeGallons) ?? "" }
        if pricePerGallon.isEmpty || !draft.isManuallyEdited(.unitPrice) {
            pricePerGallon = text(draft.unitPrice) ?? ""
        }
        if totalCost.isEmpty || !draft.isManuallyEdited(.totalCost) { totalCost = text(draft.totalCost) ?? "" }
        if let level = draft.fuelLevelRemaining {
            fuelLevelRemaining = NSDecimalNumber(decimal: level).doubleValue
        }
    }

    @MainActor
    private func resumeCaptureSession(_ sessionID: UUID) async {
        do {
            let repository = SwiftDataCaptureSessionRepository(container: modelContext.container)
            guard let session = try await repository.find(id: sessionID),
                  session.kind == .fillUp,
                  let vehicleID = session.vehicleID,
                  vehicles.contains(where: { $0.id == vehicleID }) else {
                throw CaptureSessionError.notFound
            }
            selectedVehicleID = vehicleID
            date = session.draft.occurredAt ?? session.createdAt
            captureSessionID = sessionID
            captureDraft = session.draft
            if await analyzeImages(persistCurrentValues: false) { wizardStep = .review }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func previousClusterReading(for vehicle: Vehicle) -> InstrumentClusterReading? {
        let snapshots = snapshotEvents.compactMap { snapshot -> (Date, InstrumentClusterReading)? in
            guard snapshot.vehicle?.id == vehicle.id,
                  snapshot.date < date,
                  let trip = snapshot.tripMilesOriginal
                    ?? snapshot.tripKilometers.map(UnitConversion.kilometersToMiles)
            else { return nil }
            let odometer = snapshot.odometerMilesOriginal
                ?? UnitConversion.kilometersToMiles(snapshot.odometerKilometers)
            return (
                snapshot.date,
                InstrumentClusterReading(odometerMiles: odometer, tripMiles: trip)
            )
        }
        let fills = fillEvents.compactMap { fill -> (Date, InstrumentClusterReading)? in
            guard fill.id != event?.id,
                  fill.vehicle?.id == vehicle.id,
                  fill.date < date,
                  let trip = fill.tripMilesOriginal
                    ?? fill.tripKilometers.map(UnitConversion.kilometersToMiles)
            else { return nil }
            let odometer = fill.odometerMilesOriginal
                ?? UnitConversion.kilometersToMiles(fill.odometerKilometers)
            return (
                fill.date,
                InstrumentClusterReading(odometerMiles: odometer, tripMiles: trip)
            )
        }
        return (snapshots + fills).max(by: { $0.0 < $1.0 })?.1
    }

    @MainActor
    private func continueFromEvidence() async {
        if await analyzeImages() { wizardStep = .review }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            draftAutosaveTask?.cancel()
            if event == nil, !(await persistCurrentDraft()) { return }
            performSave()
        }
    }

    private func performSave() {
        if event == nil, hasUnresolvedCriticalField || needsFuelLevelConfirmation && !fuelLevelReviewed {
            wizardStep = .review
            errorMessage = "Revisa los campos en conflicto y confirma manualmente el nivel del medidor."
            return
        }
        guard let vehicle = selectedVehicle else {
            errorMessage = "Selecciona un vehiculo."
            return
        }
        guard let odometerMilesValue = odometerMiles.asDouble,
              let gallonsValue = gallons.asDecimalDouble,
              let pricePerGallonValue = pricePerGallon.asDecimalDouble,
              let totalCostValue = totalCost.asDecimalDouble else {
            errorMessage = "Completa odometro, galones, precio y total con valores numericos."
            return
        }

        let odometerKilometersValue = normalizedKilometers(forInputDistance: odometerMilesValue, unit: vehicle.odometerUnit)
        let odometerMilesOriginalValue = normalizedMiles(forInputDistance: odometerMilesValue, unit: vehicle.odometerUnit)
        let tripMilesOriginalValue = tripMiles.asDouble.map { normalizedMiles(forInputDistance: $0, unit: vehicle.odometerUnit) }
        let tripKilometersValue = tripMiles.asDouble.map { normalizedKilometers(forInputDistance: $0, unit: vehicle.odometerUnit) }
        let integrityID = event?.id ?? UUID()
        let integrityInput = EventIntegrityInput(
            reading: EventIntegrityReading(
                id: integrityID, occurredAt: date,
                odometerKilometers: Decimal(string: String(odometerKilometersValue)) ?? 0,
                tripKilometers: tripKilometersValue.flatMap { Decimal(string: String($0)) }
            ),
            fuelLevelRemaining: Decimal(string: String(fuelLevelRemaining)) ?? -1,
            fuelScaleMax: Decimal(string: String(vehicle.fuelScaleMax)) ?? 0,
            fuelScaleStep: Decimal(string: String(vehicle.fuelScaleStep)) ?? 0,
            financial: .init(gallons: Decimal(string: String(gallonsValue)) ?? 0,
                             unitPrice: Decimal(string: String(pricePerGallonValue)) ?? 0,
                             totalCost: Decimal(string: String(totalCostValue)) ?? 0),
            overrideReason: odometerOverrideReason
        )

        let normalizedFuelLevel = FuelLevelScale.normalize(
            fuelLevelRemaining,
            maxValue: vehicle.fuelScaleMax,
            step: vehicle.fuelScaleStep
        )
        let coordinate = EventLocationPolicy.resolvedCoordinate(
            currentLatitude: locationService.currentCoordinate?.latitude,
            currentLongitude: locationService.currentCoordinate?.longitude,
            existingLatitude: event?.latitude,
            existingLongitude: event?.longitude
        )
        func populate(_ fillEvent: FuelFillEvent, vehicle: Vehicle) {
            fillEvent.vehicle = vehicle
            fillEvent.date = date
            fillEvent.odometerMilesOriginal = odometerMilesOriginalValue
            fillEvent.odometerKilometers = odometerKilometersValue
            fillEvent.tripMilesOriginal = tripMilesOriginalValue
            fillEvent.tripKilometers = tripKilometersValue
            fillEvent.gallons = gallonsValue
            fillEvent.pricePerGallon = pricePerGallonValue
            fillEvent.totalCost = totalCostValue
            fillEvent.isFullTank = isFullTank
            fillEvent.stationName = stationName.trimmed
            fillEvent.fuelLevelRemaining = normalizedFuelLevel
            fillEvent.notes = notes.trimmed
            fillEvent.invoiceOCRText = invoiceOCRText
            fillEvent.odometerOCRText = odometerOCRText
            fillEvent.fuelLevelOCRText = fuelLevelOCRText
            fillEvent.latitude = coordinate?.latitude
            fillEvent.longitude = coordinate?.longitude
            fillEvent.updatedAt = .now
        }

        do {
            if event == nil {
                guard let captureSessionID, let captureSessionRevision else {
                    errorMessage = "Analiza o crea la sesión antes de guardar el llenado."
                    return
                }
                var finalDraft = captureDraft ?? CaptureDraft()
                finalDraft.occurredAt = date
                finalDraft.odometerKilometers = Decimal(string: String(odometerKilometersValue))
                finalDraft.tripKilometers = tripKilometersValue.flatMap { Decimal(string: String($0)) }
                finalDraft.fuelLevelRemaining = Decimal(string: String(normalizedFuelLevel))
                finalDraft.volumeGallons = Decimal(string: String(gallonsValue))
                finalDraft.unitPrice = Decimal(string: String(pricePerGallonValue))
                finalDraft.totalCost = Decimal(string: String(totalCostValue))
                finalDraft.isFullTank = isFullTank
                finalDraft.stationName = stationName.trimmed
                finalDraft.notes = notes.trimmed
                finalDraft.odometerOverrideReason = odometerOverrideReason.trimmed
                _ = try CaptureConfirmationService.confirm(
                    container: modelContext.container, sessionID: captureSessionID,
                    expectedRevision: captureSessionRevision, vehicleID: vehicle.id,
                    kind: .fillUp, finalDraft: finalDraft,
                    images: [.invoice: invoiceImage, .odometer: odometerImage,
                             .fuelLevel: fuelLevelImage], integrityInput: integrityInput
                ) { storedVehicle, context in
                    let fillEvent = FuelFillEvent(id: integrityID, vehicle: storedVehicle)
                    populate(fillEvent, vehicle: storedVehicle)
                    context.insert(fillEvent)
                    try SyncMetadataMaintainer.recordChange(
                        ownerID: fillEvent.id, kind: "fuelEntry",
                        createdAt: fillEvent.createdAt, updatedAt: fillEvent.updatedAt,
                        in: context
                    )
                    return fillEvent.id
                }
                Task { await ReminderService.shared.captureLogged() }
                self.captureSessionID = nil
                dismiss()
                return
            }
            guard let fillEvent = event else { return }
            let integrityResult = try EventIntegrityService.validate(integrityInput,
                                                                      vehicleID: vehicle.id,
                                                                      in: modelContext)
            populate(fillEvent, vehicle: vehicle)
            EventIntegrityService.recordOverride(integrityResult, input: integrityInput,
                                                 eventID: fillEvent.id, sessionID: nil,
                                                 in: modelContext)
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
            try SyncMetadataMaintainer.recordChange(ownerID: fillEvent.id, kind: "fuelEntry",
                                                    createdAt: fillEvent.createdAt,
                                                    updatedAt: fillEvent.updatedAt,
                                                    in: modelContext)
            try modelContext.save()
            Task {
                await ReminderService.shared.captureLogged()
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var draftSignature: String {
        [selectedVehicleID?.uuidString ?? "", String(date.timeIntervalSince1970),
         odometerMiles, tripMiles, gallons, pricePerGallon, totalCost,
         String(isFullTank), stationName, notes, String(fuelLevelRemaining),
         odometerOverrideReason,
         String(fuelLevelReviewed)].joined(separator: "|")
    }

    private func scheduleDraftAutosave(immediate: Bool = false) {
        draftAutosaveTask?.cancel()
        guard event == nil, captureSessionID != nil,
              wizardStep == .review || wizardStep == .confirm else { return }
        draftAutosaveTask = Task {
            if !immediate { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            _ = await persistCurrentDraft()
        }
    }

    @MainActor
    private func persistCurrentDraft() async -> Bool {
        guard let sessionID = captureSessionID, let vehicle = selectedVehicle else { return false }
        do {
            let repository = SwiftDataCaptureSessionRepository(container: modelContext.container)
            guard let current = try await repository.find(id: sessionID),
                  current.state == .review, current.vehicleID == vehicle.id else {
                throw CaptureSessionError.invalidTransition
            }
            var draft = current.draft
            draft.occurredAt = date
            draft.setManualNumber(odometerMiles.asDouble.flatMap {
                Decimal(string: String(normalizedKilometers(forInputDistance: $0, unit: vehicle.odometerUnit)))
            }, for: .odometerKilometers)
            draft.setManualNumber(tripMiles.asDouble.flatMap {
                Decimal(string: String(normalizedKilometers(forInputDistance: $0, unit: vehicle.odometerUnit)))
            }, for: .tripKilometers)
            if !needsFuelLevelConfirmation || fuelLevelReviewed {
                draft.setManualNumber(Decimal(string: String(fuelLevelRemaining)), for: .fuelLevelRemaining)
            }
            draft.setManualNumber(gallons.asDecimalDouble.flatMap { Decimal(string: String($0)) },
                                  for: .volumeGallons)
            draft.setManualNumber(pricePerGallon.asDecimalDouble.flatMap { Decimal(string: String($0)) },
                                  for: .unitPrice)
            draft.setManualNumber(totalCost.asDecimalDouble.flatMap { Decimal(string: String($0)) },
                                  for: .totalCost)
            draft.isFullTank = isFullTank
            draft.stationName = stationName.trimmed
            draft.notes = notes.trimmed
            draft.odometerOverrideReason = odometerOverrideReason.trimmed
            let saved = try await repository.updateDraft(id: sessionID,
                                                         expectedRevision: current.revision,
                                                         draft: draft)
            captureSessionRevision = saved.revision
            captureDraft = saved.draft
            return true
        } catch {
            errorMessage = "No se pudo conservar el borrador: \(error.localizedDescription)"
            return false
        }
    }

    private var needsFuelLevelConfirmation: Bool {
        guard fuelLevelImage != nil,
              let status = captureFieldResults.first(where: { $0.field == .fuelLevelRemaining }) else {
            return false
        }
        return status.band == .low || status.band == .critical
    }

    private var hasUnresolvedCriticalField: Bool {
        captureFieldResults.contains { result in
            result.band == .critical && !manuallyResolved(result.field)
        }
    }

    private func manuallyResolved(_ field: CaptureField) -> Bool {
        switch field {
        case .odometerKilometers: odometerMiles.asDouble != nil
        case .tripKilometers: true // Trip is optional for a fill-up.
        case .fuelLevelRemaining: fuelLevelReviewed
        case .volumeGallons: gallons.asDecimalDouble != nil
        case .unitPrice: pricePerGallon.asDecimalDouble != nil
        case .totalCost: totalCost.asDecimalDouble != nil
        case .stationName: !stationName.trimmed.isEmpty
        case .occurredAt: true
        }
    }

    private func loadExistingData() {
        selectedVehicleID = event?.vehicle?.id ?? vehicles.first?.id
        date = event?.date ?? .now
        odometerMiles = event.flatMap { storedDistanceInput(odometerKilometers: $0.odometerKilometers, odometerMilesOriginal: $0.odometerMilesOriginal, vehicle: $0.vehicle) } ?? ""
        tripMiles = event.flatMap { storedDistanceInput(odometerKilometers: $0.tripKilometers, odometerMilesOriginal: $0.tripMilesOriginal, vehicle: $0.vehicle) } ?? ""
        gallons = event.map { String($0.gallons) } ?? ""
        pricePerGallon = event.map { String($0.pricePerGallon) } ?? ""
        totalCost = event.map { String($0.totalCost) } ?? ""
        isFullTank = event?.isFullTank ?? true
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

    private func displayDecimal(
        _ value: String,
        prefix: String = "",
        suffix: String = "",
        formatter: (Double, String) -> String = CartrackFormatters.decimal
    ) -> String {
        guard let parsed = value.asDecimalDouble else { return "Pendiente" }
        let formatted = formatter(parsed, suffix)
        return "\(prefix)\(formatted)"
    }

    private func formatOCRDistanceInput(_ miles: Double) -> String {
        let inputValue = odometerUnit == .miles ? miles : UnitConversion.milesToKilometers(miles)
        return CartrackFormatters.decimal(inputValue)
    }

    private func normalizedKilometers(forInputDistance value: Double, unit: OdometerUnit) -> Double {
        switch unit {
        case .miles: UnitConversion.milesToKilometers(value)
        case .kilometers: value
        }
    }

    private func normalizedMiles(forInputDistance value: Double, unit: OdometerUnit) -> Double {
        switch unit {
        case .miles: value
        case .kilometers: UnitConversion.kilometersToMiles(value)
        }
    }

    private func storedDistanceInput(
        odometerKilometers: Double?,
        odometerMilesOriginal: Double?,
        vehicle: Vehicle?
    ) -> String {
        guard let vehicle else { return "" }
        let value: Double?
        switch vehicle.odometerUnit {
        case .miles:
            value = odometerMilesOriginal ?? odometerKilometers.map(UnitConversion.kilometersToMiles)
        case .kilometers:
            value = odometerKilometers
        }
        return value.map { CartrackFormatters.decimal($0) } ?? ""
    }
}
