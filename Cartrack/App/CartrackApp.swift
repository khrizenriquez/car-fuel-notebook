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
        context.insert(FuelFillEvent(date: date(day: 1), vehicle: bmw, odometerKilometers: 1_000, gallons: 10, pricePerGallon: 30, totalCost: 300))
        context.insert(FuelFillEvent(date: date(day: 12), vehicle: bmw, odometerKilometers: 1_240, gallons: 12, pricePerGallon: 35, totalCost: 420))
        context.insert(SnapshotEvent(date: date(day: 13), vehicle: bmw, odometerKilometers: 1_300, fuelLevelRemaining: 6.5))
        context.insert(FuelFillEvent(date: date(day: 2), vehicle: toyota, odometerKilometers: 5_000, gallons: 18, pricePerGallon: 30, totalCost: 540))
        context.insert(FuelFillEvent(date: date(day: 14), vehicle: toyota, odometerKilometers: 5_500, gallons: 20, pricePerGallon: 35, totalCost: 700))
        context.insert(SnapshotEvent(date: date(day: 15), vehicle: toyota, odometerKilometers: 5_620, fuelLevelRemaining: 7))
        try context.save()
    }

    private static func date(day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: day)) ?? .now
    }
}

private struct PersistenceUnavailableView: View {
    let error: Error

    var body: some View {
        ContentUnavailableView {
            Label("Cartrack no pudo abrir la base local", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Tus datos no se borraron automaticamente. Cierra y vuelve a abrir la app. Si el problema sigue, revisa el almacenamiento disponible antes de usar Reset total.")
        } actions: {
            Text(error.localizedDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}
