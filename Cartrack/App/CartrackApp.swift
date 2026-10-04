import SwiftData
import SwiftUI

@main
struct CartrackApp: App {
    private let bootstrapResult: Result<ModelContainer, Error>

    init() {
        do {
            let arguments = ProcessInfo.processInfo.arguments
            let isUITesting = arguments.contains("--uitesting")
            let container = try CartrackModelContainer.make(isStoredInMemoryOnly: isUITesting)
            if isUITesting && arguments.contains("--seed-multivehicle") {
                try UITestSeedData.insertMultiVehicleScenario(into: container)
            }
            if isUITesting && arguments.contains("--seed-latest-z4-snapshot") {
                try UITestSeedData.insertLatestZ4SnapshotScenario(into: container)
            }
            _ = try SwiftDataCaptureSessionRepository.recoverOnLaunch(in: container)
            bootstrapResult = .success(container)
        } catch {
            bootstrapResult = .failure(error)
        }
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrapResult {
            case .success(let modelContainer):
                RootTabView()
                    .modelContainer(modelContainer)
            case .failure(let error):
                PersistenceUnavailableView(error: error)
            }
        }
    }
}

private enum UITestSeedData {
    static func insertMultiVehicleScenario(into container: ModelContainer) throws {
        let context = ModelContext(container)
        let bmw = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003)
        let toyota = Vehicle(name: "Commuter", make: "Toyota", modelName: "Yaris", year: 2020)
        context.insert(bmw)
        context.insert(toyota)
        context.insert(FuelFillEvent(date: date(day: 1), vehicle: bmw, odometerKilometers: 1_000, gallons: 10, pricePerGallon: 30, totalCost: 300, stationName: "Demo Station North", latitude: 37.3349, longitude: -122.0090))
        context.insert(FuelFillEvent(date: date(day: 12), vehicle: bmw, odometerKilometers: 1_240, gallons: 12, pricePerGallon: 35, totalCost: 420, stationName: "Demo Station West", latitude: 37.3230, longitude: -122.0322))
        context.insert(SnapshotEvent(date: date(day: 13), vehicle: bmw, odometerKilometers: 1_300, fuelLevelRemaining: 6.5))
        context.insert(FuelFillEvent(date: date(day: 2), vehicle: toyota, odometerKilometers: 5_000, gallons: 18, pricePerGallon: 30, totalCost: 540, stationName: "Demo Station South", latitude: 37.3087, longitude: -122.0234))
        context.insert(FuelFillEvent(date: date(day: 14), vehicle: toyota, odometerKilometers: 5_500, gallons: 20, pricePerGallon: 35, totalCost: 700, stationName: "Demo Station East", latitude: 37.3399, longitude: -121.9875))
        context.insert(SnapshotEvent(date: date(day: 15), vehicle: toyota, odometerKilometers: 5_620, fuelLevelRemaining: 7))
        try context.save()
    }

    static func insertLatestZ4SnapshotScenario(into container: ModelContainer) throws {
        let context = ModelContext(container)
        try deleteAllData(in: context)

        let bmw = Vehicle(
            name: "Roadster",
            make: "BMW",
            modelName: "Z4",
            year: 2003,
            engine: "2.5i",
            tankCapacityGallons: 14.0,
            fuelScaleMax: 8,
            fuelScaleStep: 0.25,
            fuelEconomyReferenceKilometersPerGallon: 29.0
        )
        context.insert(bmw)

        let texacoFill = FuelFillEvent(
            date: date(day: 9, hour: 19, minute: 56),
            vehicle: bmw,
            odometerMilesOriginal: 109_162,
            odometerKilometers: UnitConversion.milesToKilometers(109_162),
            tripMilesOriginal: 0,
            tripKilometers: 0,
            gallons: 3.791,
            pricePerGallon: 39.57,
            totalCost: 150.00,
            isFullTank: true,
            stationName: "Texaco San Rafael",
            fuelLevelRemaining: 8
        )
        let previousSnapshot = SnapshotEvent(
            date: date(day: 10, hour: 22, minute: 50),
            vehicle: bmw,
            odometerMilesOriginal: 109_394,
            odometerKilometers: UnitConversion.milesToKilometers(109_394),
            tripMilesOriginal: 232.9,
            tripKilometers: UnitConversion.milesToKilometers(232.9),
            fuelLevelRemaining: 1.5
        )
        let reserveSnapshot = SnapshotEvent(
            date: date(day: 11, hour: 17, minute: 19),
            vehicle: bmw,
            odometerMilesOriginal: 109_413,
            odometerKilometers: UnitConversion.milesToKilometers(109_413),
            tripMilesOriginal: 251.0,
            tripKilometers: UnitConversion.milesToKilometers(251.0),
            fuelLevelRemaining: 1.0
        )

        context.insert(texacoFill)
        context.insert(previousSnapshot)
        context.insert(reserveSnapshot)
        try context.save()
    }

    private static func deleteAllData(in context: ModelContext) throws {
        try context.fetch(FetchDescriptor<CaptureSessionRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<OCRFieldEvidence>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<LocalPhotoAsset>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<V2RecordExtras>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<SyncMetadataRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<ImageAsset>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<SnapshotEvent>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<FuelFillEvent>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<MonthlyManualAdjustment>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Vehicle>()).forEach(context.delete)
        try context.save()
    }

    private static func date(day: Int) -> Date {
        date(day: day, hour: 0, minute: 0)
    }

    private static func date(day: Int, hour: Int, minute: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let currentComponents = calendar.dateComponents([.year, .month], from: .now)
        return calendar.date(from: DateComponents(year: currentComponents.year, month: currentComponents.month, day: day, hour: hour, minute: minute)) ?? .now
    }
}

private struct PersistenceUnavailableView: View {
    let error: Error

    var body: some View {
        ContentUnavailableView {
            Label("Cartrack no pudo abrir la base local", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Tus datos no se borraron automaticamente. Cierra y vuelve a abrir la app. Si el problema sigue, revisa el almacenamiento disponible antes de borrar datos de un vehiculo.")
        } actions: {
            Text(error.localizedDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}
