import SwiftData
import SwiftUI
import UIKit

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
            Section("Vehiculo") {
                Picker("Vehiculo", selection: $selectedVehicleID) {
                    ForEach(vehicles, id: \.id) { vehicle in
                        Text(vehicle.displayName).tag(Optional(vehicle.id))
                    }
                }
            }

            Section("Lectura") {
                DatePicker("Fecha", selection: $date, displayedComponents: [.date, .hourAndMinute])
                TextField("Odometro en millas", text: $odometerMiles)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("snapshot.odometer")
                TextField("Trip en millas (opcional)", text: $tripMiles)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("snapshot.trip")
                VStack(alignment: .leading) {
                    HStack {
                        Text("Espacios restantes")
                        Spacer()
                        Text(CartrackFormatters.decimal(fuelLevelRemaining))
                    }
                    Slider(
                        value: $fuelLevelRemaining,
                        in: 0...(selectedVehicle?.fuelScaleMax ?? FuelLevelScale.defaultMax),
                        step: selectedVehicle?.fuelScaleStep ?? FuelLevelScale.defaultStep
                    )
                }
                TextField("Notas", text: $notes, axis: .vertical)
                    .accessibilityIdentifier("snapshot.notes")
            }

            ImageCaptureField(
                title: "Odometro",
                caption: "Captura separada del odometro o cluster.",
                existingPath: $existingOdometerPath,
                image: $odometerImage
            )
            ImageCaptureField(
                title: "Nivel de tanque",
                caption: "Captura separada del nivel de combustible.",
                existingPath: $existingFuelLevelPath,
                image: $fuelLevelImage
            )

            Section("OCR local") {
                Button(isAnalyzing ? "Analizando..." : "Analizar imagenes") {
                    Task { await analyzeImages() }
                }
                .disabled(isAnalyzing)
                if !odometerOCRText.isEmpty || !fuelLevelOCRText.isEmpty {
                    Text([odometerOCRText, fuelLevelOCRText].filter { !$0.isEmpty }.joined(separator: "\n\n"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(event == nil ? "Nuevo snapshot" : "Editar snapshot")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save)
                    .accessibilityIdentifier("snapshot.save")
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

    private func save() {
        guard let vehicle = selectedVehicle, let odometerMilesValue = odometerMiles.asDouble else {
            errorMessage = "Selecciona vehiculo y odometro valido."
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
        snapshot.latitude = locationService.currentCoordinate?.latitude
        snapshot.longitude = locationService.currentCoordinate?.longitude
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
                await ReminderService.shared.scheduleInactivityReminder(afterHours: UserDefaults.standard.double(forKey: "settings.reminder.hours").nonZeroOrDefault(72))
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
}
