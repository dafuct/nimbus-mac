import SwiftUI
import NimbusViewModels

@main
struct NimbusApp: App {
    @State private var environment = AppEnvironment()
    @State private var health = HealthViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(environment.localizer)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)   // custom dark chrome; real traffic lights overlay the sidebar
        .defaultSize(width: 1280, height: 824)

        // Health Monitor menu-bar item — read-only, no "free RAM" button.
        MenuBarExtra("Nimbus", systemImage: "gauge.with.dots.needle.67percent") {
            HealthMenuView(viewModel: health)
                .environment(environment.localizer)
                .onAppear { health.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
