import CoreLocation
import SwiftData
import SwiftUI
import UIKit

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
            Section("Vehiculo") {
                Picker("Vehiculo", selection: $selectedVehicleID) {
                    ForEach(vehicles, id: \.id) { vehicle in
                        Text(vehicle.displayName).tag(Optional(vehicle.id))
                    }
                }
            }

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
                    .accessibilityIdentifier("fill.notes")
            }

            if let tripWarning {
                Section("Revision") {
                    Label(tripWarning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

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
                caption: "Foto separada del nivel de combustible si lo deseas documentar.",
                existingPath: $existingFuelLevelPath,
                image: $fuelLevelImage
            )

            Section("OCR local") {
                Button(isAnalyzing ? "Analizando..." : "Analizar imagenes") {
                    Task { await analyzeImages() }
                }
                .disabled(isAnalyzing)

                if !invoiceOCRText.isEmpty {
                    Text(invoiceOCRText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(event == nil ? "Nuevo llenado" : "Editar llenado")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save)
                    .accessibilityIdentifier("fill.save")
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
        fillEvent.latitude = locationService.currentCoordinate?.latitude
        fillEvent.longitude = locationService.currentCoordinate?.longitude
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
}
