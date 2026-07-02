import SwiftUI
import NimbusKit
import NimbusViewModels

/// Top-level shell, skinned to `Nimbus.dc.html`: a custom dark sidebar (logo,
/// Smart Scan, "Очищення" section, system-status card, bottom nav) + a main pane
/// with the design's title·subtitle header bar.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(Localizer.self) private var loc
    @State private var selection: Module = .smartScan
    @State private var onboardingStep: Int? = UserDefaults.standard.bool(forKey: "nimbus_onboarded") ? nil : 0

    enum Module: String, CaseIterable, Identifiable {
        case smartScan, cleanup, lens, duplicates, uninstaller, performance, health, settings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .smartScan: return "Smart Scan"
            case .cleanup: return "Системний мотлох"
            case .lens: return "Space Lens"
            case .duplicates: return "Дублікати та фото"
            case .uninstaller: return "Застосунки"
            case .performance: return "Обслуговування"
            case .health: return "Стан системи"
            case .settings: return "Налаштування"
            }
        }
        var subtitle: String {
            switch self {
            case .smartScan: return "Готово до сканування"
            case .cleanup: return "Безпечно прибрати системні файли"
            case .lens: return "Що займає місце на диску"
            case .duplicates: return "Однакові й схожі файли"
            case .uninstaller: return "Видалення разом із залишками"
            case .performance: return "Задачі обслуговування"
            case .health: return "Реальний стан вашого Mac"
            case .settings: return "Преференції та винятки"
            }
        }
        var icon: String {
            switch self {
            case .smartScan: return "sparkles"
            case .cleanup: return "wand.and.stars"
            case .lens: return "square.grid.2x2.fill"
            case .duplicates: return "doc.on.doc.fill"
            case .uninstaller: return "macwindow"
            case .performance: return "bolt.fill"
            case .health: return "waveform.path.ecg"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            mainPane
        }
        .background(Theme.Colors.window)
        .preferredColorScheme(.dark)   // Nimbus is dark-only by design
        .overlay {
            if onboardingStep != nil {
                OnboardingView(step: $onboardingStep)
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Reserve space for the real macOS traffic lights (hidden title bar).
            Color.clear.frame(height: 28)

            logo
                .padding(.horizontal, 16)
                .padding(.top, 6).padding(.bottom, 16)

            navRow(.smartScan).padding(.horizontal, 12)

            sectionHeader(loc("Очищення"))
            VStack(spacing: 2) {
                navRow(.cleanup, badge: sizeBadge(env.cleanup.foundBytes))
                navRow(.lens)
                navRow(.duplicates, badge: sizeBadge(env.duplicates.foundReclaimableBytes))
                navRow(.uninstaller)
                navRow(.performance)
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 12)

            systemStatusCard.padding(.horizontal, 12).padding(.bottom, 8)

            Divider().overlay(Theme.Colors.hairlineSoft)
            VStack(spacing: 2) {
                navRow(.health)
                navRow(.settings)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 14)
        }
        .frame(width: 240)
        .background(Theme.Gradients.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.Colors.hairline).frame(width: 0.5)
        }
    }

    private var logo: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.Gradients.logo)
                .frame(width: 34, height: 34)
                .overlay(Circle().fill(.white.opacity(0.92)).frame(width: 13, height: 13))
                .shadow(color: Theme.Colors.accent.opacity(0.55), radius: 7, y: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text("Nimbus").font(Theme.Font.body(15, .bold)).foregroundStyle(Theme.Colors.textPrimary)
                Text(loc("Догляд за Mac")).font(Theme.Font.body(11, .medium)).foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.Font.body(10.5, .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.Colors.textQuaternary)
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 7)
    }

    /// Sidebar size chip: the real reclaimable total from the last scan, or `nil`
    /// (no chip) until a scan has found something — never a stale placeholder.
    /// Reading the view models' observable state here makes the chip refresh on
    /// scan and after a cleanup re-scans.
    private func sizeBadge(_ bytes: Int64) -> String? {
        bytes > 0 ? bytes.formattedBytes : nil
    }

    private func navRow(_ module: Module, badge: String? = nil) -> some View {
        let active = selection == module
        return Button {
            selection = module
        } label: {
            HStack(spacing: 9) {
                Image(systemName: module.icon)
                    .font(.system(size: 14))
                    .frame(width: 18)
                Text(loc(module.title)).font(Theme.Font.body(13, active ? .semibold : .medium))
                Spacer(minLength: 4)
                if let badge {
                    Text(badge).font(Theme.Font.mono(10.5)).opacity(0.8)
                }
            }
            .foregroundStyle(active ? Theme.Colors.accentLighter : Theme.Colors.textControl)
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(active ? Theme.Colors.accent.opacity(0.13) : .clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var systemStatusCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(loc("Стан системи")).font(Theme.Font.body(11, .semibold)).foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Theme.Colors.success).frame(width: 7, height: 7)
                        .shadow(color: Theme.Colors.success, radius: 4)
                    Text(loc("Добре")).font(Theme.Font.body(10.5, .semibold)).foregroundStyle(Theme.Colors.success)
                }
            }
            HStack(spacing: 6) {
                miniBar(label: loc("Тиск пам'яті"), fraction: 0.34, color: Theme.Colors.success)
                miniBar(label: loc("Диск"), fraction: 0.71, color: Theme.Colors.warning)
            }
        }
        .padding(.vertical, 11).padding(.horizontal, 13)
        .background(Theme.Colors.surfaceFaint, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
    }

    private func miniBar(label: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(Theme.Font.body(9.5)).foregroundStyle(Theme.Colors.textTertiary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule().fill(color).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: Main pane

    private var mainPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Text(loc(selection.title)).font(Theme.Font.body(13.5, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                Text("·").foregroundStyle(Theme.Colors.textQuaternary)
                Text(loc(selection.subtitle)).font(Theme.Font.body(12.5, .medium)).foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 26)
            .frame(height: 52)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.hairlineSoft).frame(height: 0.5) }

            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.Colors.window)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .smartScan: SmartScanView(viewModel: env.smartScan, onOpenModule: { selection = $0 })
        case .lens: SpaceLensView(viewModel: env.spaceLens)
        case .duplicates: DuplicatesView(viewModel: env.duplicates)
        case .cleanup: CleanupView(viewModel: env.cleanup)
        case .health: HealthView(viewModel: env.health)
        case .settings: SettingsView(viewModel: env.settings, onReplayOnboarding: { onboardingStep = 0 })
        case .uninstaller: UninstallerView(viewModel: env.uninstaller)
        case .performance: PerformanceView(viewModel: env.performance)
        }
    }
}

struct PlaceholderView: View {
    @Environment(Localizer.self) private var loc
    let title: String
    var body: some View {
        VStack(spacing: 8) {
            Text(loc(title)).font(Theme.Font.display(20)).foregroundStyle(Theme.Colors.textSecondary)
            Text(loc("Цей модуль готується… (домен реалізовано й покрито тестами в NimbusKit)"))
                .font(Theme.Font.body(13)).foregroundStyle(Theme.Colors.textQuaternary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.window)
    }
}
