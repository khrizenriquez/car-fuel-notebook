import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.xyaxis.line")
            }
            .accessibilityIdentifier("tab.dashboard")

            NavigationStack {
                CaptureHomeView()
            }
            .tabItem {
                Label("Capturar", systemImage: "camera.viewfinder")
            }
            .accessibilityIdentifier("tab.capture")

            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("Historial", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            }
            .accessibilityIdentifier("tab.history")

            NavigationStack {
                VehiclesView()
            }
            .tabItem {
                Label("Vehiculos", systemImage: "car.side")
            }
            .accessibilityIdentifier("tab.vehicles")

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Ajustes", systemImage: "gearshape")
            }
            .accessibilityIdentifier("tab.settings")
        }
        .tint(Color(red: 0.15, green: 0.45, blue: 0.28))
    }
}
