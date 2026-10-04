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
    @Query(sort: \SnapshotEvent.date, order: .reverse) private var snapshotEvents: [SnapshotEvent]
    @Query(sort: \FuelFillEvent.date, order: .reverse) private var fillEvents: [FuelFillEvent]

    private let ocrService = OCRService()
    @StateObject private var locationService = LocationService()

    let event: SnapshotEvent?
    let resumeSessionID: UUID?

    @State private var selectedVehicleID: UUID?
    @State private var date = Date()
    @State private var odometerMiles = ""
    @State private var tripMiles = ""
    @State private var notes = ""
    @State private var odometerOverrideReason = ""
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
    @State private var captureSessionID: UUID?
    @State private var captureSessionRevision: Int64?
    @State private var captureDraft: CaptureDraft?
    @State private var captureFieldResults: [FieldResult] = []
    @State private var captureImageIssues: [CaptureImageKind: [CaptureImageIssue]] = [:]
    @State private var fuelLevelReviewed = false
    @State private var draftAutosaveTask: Task<Void, Never>?
    @State private var isSaving = false
    @FocusState private var focusedField: SnapshotFocusedField?

    init(event: SnapshotEvent? = nil, resumeSessionID: UUID? = nil) {
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
                        .disabled(isSaving)
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
            CaptureConfidenceSection(fields: captureFieldResults,
                                     imageIssues: captureImageIssues,
                                     isManuallyResolved: manuallyResolved,
                                     retake: { _ in wizardStep = .evidence })
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
                        .disabled(isSaving)
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
            accessibilityPrefix: "snapshot.odometerImage",
            existingPath: $existingOdometerPath,
            image: $odometerImage
        )
        ImageCaptureField(
            title: "Nivel de tanque",
            caption: "Captura separada del nivel de combustible. Si es una aguja analogica, confirma los espacios manualmente en el siguiente paso.",
            accessibilityPrefix: "snapshot.fuelImage",
            existingPath: $existingFuelLevelPath,
            image: $fuelLevelImage
        )
    }

    private var readingSection: some View {
        Section("Lectura") {
            DatePicker("Fecha", selection: $date, displayedComponents: [.date, .hourAndMinute])
            TextField("Odometro en \(odometerUnit.inputLabel)", text: $odometerMiles)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .odometer)
                .accessibilityIdentifier("snapshot.odometer")
            TextField("Trip en \(odometerUnit.inputLabel) (opcional)", text: $tripMiles)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("snapshot.trip")
            TextField("Motivo de corrección del odómetro (solo si retrocede)", text: $odometerOverrideReason, axis: .vertical)
                .accessibilityIdentifier("snapshot.odometerOverrideReason")
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
            if needsFuelLevelConfirmation {
                Toggle("Confirmé visualmente el nivel del medidor", isOn: $fuelLevelReviewed)
                    .accessibilityIdentifier("snapshot.fuelLevel.confirmed")
            }
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
                LabeledContent("Odometro", value: display(odometerMiles, suffix: odometerUnit.rawValue))
            }
            LabeledContent("Trip", value: display(tripMiles, suffix: odometerUnit.rawValue))
            LabeledContent("Espacios restantes", value: CartrackFormatters.decimal(fuelLevelRemaining))
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
                let workflow = SnapshotCaptureWorkflow(container: modelContext.container)
                let outcome = try await workflow.analyze(
                    input: snapshotCaptureInput(for: vehicle), sessionID: captureSessionID
                )
                captureSessionID = outcome.session.id
                captureSessionRevision = outcome.session.revision
                captureDraft = outcome.session.draft
                odometerImage = outcome.images[.odometer]
                fuelLevelImage = outcome.images[.fuelLevel]
                if needsFuelLevelConfirmation { fuelLevelReviewed = false }
                captureFieldResults = outcome.fields
                captureImageIssues = outcome.imageIssues
                odometerOCRText = outcome.recognizedText.odometerText
                fuelLevelOCRText = outcome.recognizedText.fuelLevelText
                applyCaptureDraft(outcome.session.draft)
                return true
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        }
        let result = await ocrService.analyzeSnapshot(
            odometerImage: odometerImage,
            fuelLevelImage: fuelLevelImage,
            fuelScaleMax: vehicle.fuelScaleMax,
            previousClusterReading: previousClusterReading(for: vehicle)
        )
        odometerOCRText = result.odometerText
        fuelLevelOCRText = result.fuelLevelText
        odometerMiles = odometerMiles.isEmpty ? result.odometerMiles.map(formatOCRDistanceInput) ?? odometerMiles : odometerMiles
        tripMiles = tripMiles.isEmpty ? result.tripMiles.map(formatOCRDistanceInput) ?? tripMiles : tripMiles
        if let value = result.fuelLevelRemaining {
            fuelLevelRemaining = value
        }
        return true
    }

    private func snapshotCaptureInput(for vehicle: Vehicle) -> SnapshotCaptureInput {
        var images: [CaptureImageKind: UIImage] = [:]
        if let odometerImage { images[.odometer] = odometerImage }
        if let fuelLevelImage { images[.fuelLevel] = fuelLevelImage }
        let previousSnapshot = snapshotEvents
            .filter { $0.id != event?.id && $0.vehicle?.id == vehicle.id && $0.date < date }
            .max(by: { $0.date < $1.date })
        let previousFill = fillEvents
            .filter { $0.vehicle?.id == vehicle.id && $0.date < date }
            .max(by: { $0.date < $1.date })
        let previousOdometer = [previousSnapshot.map { ($0.date, $0.odometerKilometers) },
                                previousFill.map { ($0.date, $0.odometerKilometers) }]
            .compactMap { $0 }
            .max(by: { $0.0 < $1.0 })?.1
        return SnapshotCaptureInput(
            vehicleID: vehicle.id, occurredAt: date,
            fuelScaleMax: Decimal(string: String(vehicle.fuelScaleMax)) ?? 8,
            fuelScaleStep: Decimal(string: String(vehicle.fuelScaleStep)) ?? 0.25,
            previousOdometerKilometers: previousOdometer.flatMap { Decimal(string: String($0)) },
            lastFillOdometerKilometers: previousFill.flatMap { Decimal(string: String($0.odometerKilometers)) },
            previousClusterReading: previousClusterReading(for: vehicle), images: images
        )
    }

    private func applyCaptureDraft(_ draft: CaptureDraft) {
        odometerOverrideReason = draft.odometerOverrideReason ?? ""
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
        if let level = draft.fuelLevelRemaining {
            fuelLevelRemaining = NSDecimalNumber(decimal: level).doubleValue
        }
    }

    @MainActor
    private func resumeCaptureSession(_ sessionID: UUID) async {
        do {
            let repository = SwiftDataCaptureSessionRepository(container: modelContext.container)
            guard let session = try await repository.find(id: sessionID),
                  session.kind == .snapshot,
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
            guard snapshot.id != event?.id,
                  snapshot.vehicle?.id == vehicle.id,
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
            guard fill.vehicle?.id == vehicle.id,
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
        guard let odometerMilesValue = odometerMiles.asDouble else {
            moveToOdometerReview()
            errorMessage = "Completa el odometro manualmente para guardar el snapshot."
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
            financial: nil, overrideReason: odometerOverrideReason
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
        func populate(_ snapshot: SnapshotEvent, vehicle: Vehicle) {
            snapshot.vehicle = vehicle
            snapshot.date = date
            snapshot.odometerMilesOriginal = odometerMilesOriginalValue
            snapshot.odometerKilometers = odometerKilometersValue
            snapshot.tripMilesOriginal = tripMilesOriginalValue
            snapshot.tripKilometers = tripKilometersValue
            snapshot.fuelLevelRemaining = normalizedFuelLevel
            snapshot.notes = notes.trimmed
            snapshot.odometerOCRText = odometerOCRText
            snapshot.fuelLevelOCRText = fuelLevelOCRText
            snapshot.latitude = coordinate?.latitude
            snapshot.longitude = coordinate?.longitude
            snapshot.updatedAt = .now
        }

        do {
            if event == nil {
                guard let captureSessionID, let captureSessionRevision else {
                    errorMessage = "Analiza o crea la sesión antes de guardar el registro."
                    return
                }
                var finalDraft = captureDraft ?? CaptureDraft()
                finalDraft.occurredAt = date
                finalDraft.odometerKilometers = Decimal(string: String(odometerKilometersValue))
                finalDraft.tripKilometers = tripKilometersValue.flatMap { Decimal(string: String($0)) }
                finalDraft.fuelLevelRemaining = Decimal(string: String(normalizedFuelLevel))
                finalDraft.notes = notes.trimmed
                finalDraft.odometerOverrideReason = odometerOverrideReason.trimmed
                _ = try CaptureConfirmationService.confirm(
                    container: modelContext.container, sessionID: captureSessionID,
                    expectedRevision: captureSessionRevision, vehicleID: vehicle.id,
                    kind: .snapshot, finalDraft: finalDraft,
                    images: [.odometer: odometerImage, .fuelLevel: fuelLevelImage],
                    integrityInput: integrityInput
                ) { storedVehicle, context in
                    let snapshot = SnapshotEvent(id: integrityID, vehicle: storedVehicle)
                    populate(snapshot, vehicle: storedVehicle)
                    context.insert(snapshot)
                    try SyncMetadataMaintainer.recordChange(
                        ownerID: snapshot.id, kind: "usageSnapshot",
                        createdAt: snapshot.createdAt, updatedAt: snapshot.updatedAt,
                        in: context
                    )
                    return snapshot.id
                }
                Task { await ReminderService.shared.captureLogged() }
                self.captureSessionID = nil
                dismiss()
                return
            }
            guard let snapshot = event else { return }
            let integrityResult = try EventIntegrityService.validate(integrityInput,
                                                                      vehicleID: vehicle.id,
                                                                      in: modelContext)
            populate(snapshot, vehicle: vehicle)
            EventIntegrityService.recordOverride(integrityResult, input: integrityInput,
                                                 eventID: snapshot.id, sessionID: nil,
                                                 in: modelContext)
            try EventImageSynchronizer.replaceAssets(
                for: snapshot,
                images: [
                    .odometer: odometerImage,
                    .fuelLevel: fuelLevelImage,
                ],
                removedKinds: removedKinds(),
                context: modelContext
            )
            try SyncMetadataMaintainer.recordChange(ownerID: snapshot.id, kind: "usageSnapshot",
                                                    createdAt: snapshot.createdAt,
                                                    updatedAt: snapshot.updatedAt,
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
         odometerMiles, tripMiles, notes, odometerOverrideReason, String(fuelLevelRemaining),
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
        case .tripKilometers: true // Trip is optional for a usage snapshot.
        case .fuelLevelRemaining: fuelLevelReviewed
        case .volumeGallons, .unitPrice, .totalCost, .stationName, .occurredAt: false
        }
    }

    private func loadExistingData() {
        selectedVehicleID = event?.vehicle?.id ?? vehicles.first?.id
        date = event?.date ?? .now
        odometerMiles = event.flatMap { storedDistanceInput(odometerKilometers: $0.odometerKilometers, odometerMilesOriginal: $0.odometerMilesOriginal, vehicle: $0.vehicle) } ?? ""
        tripMiles = event.flatMap { storedDistanceInput(odometerKilometers: $0.tripKilometers, odometerMilesOriginal: $0.tripMilesOriginal, vehicle: $0.vehicle) } ?? ""
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
