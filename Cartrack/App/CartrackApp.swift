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
        let bmw = Vehicle(
            name: "Roadster",
            make: "BMW",
            modelName: "Z4",
            year: 2003,
            engine: "2.5i",
            tankCapacityGallons: 14.5,
            fuelScaleMax: 8,
            fuelScaleStep: 0.25,
            fuelEconomyReferenceKilometersPerGallon: 28.5
        )
        context.insert(bmw)

        let fillA = FuelFillEvent(date: date(day: 1), vehicle: bmw, odometerMilesOriginal: 107_400, odometerKilometers: UnitConversion.milesToKilometers(107_400), gallons: 11.0, pricePerGallon: 35.0, totalCost: 385.0, isFullTank: true, stationName: "Demo Station A")
        let fillB = FuelFillEvent(date: date(day: 3), vehicle: bmw, odometerMilesOriginal: 107_650, odometerKilometers: UnitConversion.milesToKilometers(107_650), gallons: 11.2, pricePerGallon: 35.0, totalCost: 392.0, isFullTank: true, stationName: "Demo Station B")
        let fillC = FuelFillEvent(date: date(day: 5), vehicle: bmw, odometerMilesOriginal: 107_905, odometerKilometers: UnitConversion.milesToKilometers(107_905), gallons: 11.4, pricePerGallon: 35.0, totalCost: 399.0, isFullTank: true, stationName: "Demo Station C")
        let latestFullFill = FuelFillEvent(date: date(day: 8), vehicle: bmw, odometerMilesOriginal: 108_162, odometerKilometers: UnitConversion.milesToKilometers(108_162), gallons: 11.3468, pricePerGallon: 34.75, totalCost: 394.30, isFullTank: true, stationName: "Monica Roxanda Guzman Go")
        let partialTexacoFill = FuelFillEvent(date: date(day: 9, hour: 19, minute: 56), vehicle: bmw, odometerMilesOriginal: 108_337, odometerKilometers: UnitConversion.milesToKilometers(108_337), tripMilesOriginal: 175.4, tripKilometers: UnitConversion.milesToKilometers(175.4), gallons: 3.791, pricePerGallon: 39.57, totalCost: 150.00, isFullTank: false, stationName: "Texaco San Rafael", fuelLevelRemaining: 4.0)
        let snapshot5366 = SnapshotEvent(date: date(day: 8, hour: 17, minute: 12), vehicle: bmw, odometerMilesOriginal: 108_288, odometerKilometers: UnitConversion.milesToKilometers(108_288), tripMilesOriginal: 126.3, tripKilometers: UnitConversion.milesToKilometers(126.3), fuelLevelRemaining: 4.25)
        let snapshot5381 = SnapshotEvent(date: date(day: 9, hour: 8, minute: 13), vehicle: bmw, odometerMilesOriginal: 108_309, odometerKilometers: UnitConversion.milesToKilometers(108_309), tripMilesOriginal: 147.6, tripKilometers: UnitConversion.milesToKilometers(147.6), fuelLevelRemaining: 4.0)
        let snapshot5413 = SnapshotEvent(date: date(day: 9, hour: 18, minute: 3), vehicle: bmw, odometerMilesOriginal: 108_335, odometerKilometers: UnitConversion.milesToKilometers(108_335), tripMilesOriginal: 173.7, tripKilometers: UnitConversion.milesToKilometers(173.7), fuelLevelRemaining: 3.25)
        let snapshot5416 = SnapshotEvent(date: date(day: 9, hour: 19, minute: 52), vehicle: bmw, odometerMilesOriginal: 108_337, odometerKilometers: UnitConversion.milesToKilometers(108_337), tripMilesOriginal: 175.4, tripKilometers: UnitConversion.milesToKilometers(175.4), fuelLevelRemaining: 3.25)
        let snapshot5419 = SnapshotEvent(date: date(day: 9, hour: 21, minute: 1), vehicle: bmw, odometerMilesOriginal: 108_355, odometerKilometers: UnitConversion.milesToKilometers(108_355), tripMilesOriginal: 193.1, tripKilometers: UnitConversion.milesToKilometers(193.1), fuelLevelRemaining: 4.0)
        let snapshot5421 = SnapshotEvent(date: date(day: 10, hour: 7, minute: 46), vehicle: bmw, odometerMilesOriginal: 108_365, odometerKilometers: UnitConversion.milesToKilometers(108_365), tripMilesOriginal: 203.3, tripKilometers: UnitConversion.milesToKilometers(203.3), fuelLevelRemaining: 3.85)
        let snapshot5427 = SnapshotEvent(date: date(day: 10, hour: 13, minute: 55), vehicle: bmw, odometerMilesOriginal: 108_375, odometerKilometers: UnitConversion.milesToKilometers(108_375), tripMilesOriginal: 213.1, tripKilometers: UnitConversion.milesToKilometers(213.1), fuelLevelRemaining: 3.75)

        [fillA, fillB, fillC, latestFullFill, partialTexacoFill].forEach(context.insert)
        [snapshot5366, snapshot5381, snapshot5413, snapshot5416, snapshot5419, snapshot5421, snapshot5427].forEach(context.insert)
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
