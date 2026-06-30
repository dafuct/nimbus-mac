import SwiftUI
import NimbusKit
import NimbusViewModels

/// The menu-bar Health Monitor. Reads memory pressure + top consumers via mach/ps.
/// Strictly informational — deliberately no "purge"/"free RAM" action. Localized.
struct HealthMenuView: View {
    @Environment(Localizer.self) private var loc
    @Bindable var viewModel: HealthViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(loc("Стан системи")).font(.headline)

            if let snapshot = viewModel.snapshot {
                pressureRow(snapshot)
                memoryBar(snapshot)
                Divider()
                Text(loc("Найбільші споживачі")).font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                ForEach(viewModel.topConsumers) { proc in
                    HStack {
                        Text(proc.name).lineLimit(1)
                        Spacer()
                        Text(proc.residentBytes.formattedBytes)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .font(.caption)
                }
            } else {
                ProgressView().controlSize(.small)
            }

            Divider()
            Button(loc("Відкрити Моніторинг системи")) { openActivityMonitor() }
                .buttonStyle(.borderless)
        }
        .padding(Theme.Spacing.md)
        .frame(width: 280)
    }

    private func pressureRow(_ s: MemorySnapshot) -> some View {
        HStack {
            Circle().fill(Theme.Colors.pressure(s.pressure)).frame(width: 10, height: 10)
            Text(loc("Тиск пам'яті: %@", label(s.pressure)))
            Spacer()
            Text("\(s.used.formattedBytes) / \(s.total.formattedBytes)")
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .font(.callout)
    }

    private func memoryBar(_ s: MemorySnapshot) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.surfaceElevated)
                Capsule().fill(Theme.Colors.pressure(s.pressure))
                    .frame(width: geo.size.width * s.usedFraction)
            }
        }
        .frame(height: 8)
    }

    private func label(_ level: MemoryPressureLevel) -> String {
        switch level {
        case .normal: return loc("Норма")
        case .warning: return loc("Помірний")
        case .critical: return loc("Високий")
        }
    }

    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
