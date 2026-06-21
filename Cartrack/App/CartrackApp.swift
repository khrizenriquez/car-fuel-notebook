import SwiftData
import SwiftUI

@main
struct CartrackApp: App {
    private let bootstrapResult: Result<ModelContainer, Error>

    init() {
        do {
            let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
            bootstrapResult = .success(try CartrackModelContainer.make(isStoredInMemoryOnly: isUITesting))
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
