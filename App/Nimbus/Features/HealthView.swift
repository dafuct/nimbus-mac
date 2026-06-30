import SwiftUI
import NimbusKit
import NimbusViewModels

/// In-window Health screen — live memory pressure, disk usage, and top memory
/// consumers, skinned to `Nimbus.dc.html`. Read-only: the design's core message
/// is "pressure, not free gigabytes" — we never offer to "free" RAM.
struct HealthView: View {
    @Bindable var viewModel: HealthViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statCards
                pressureCard
            }
            .padding(EdgeInsets(top: 24, leading: 28, bottom: 36, trailing: 28))
        }
        .background(Theme.Colors.window)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    private var snapshot: MemorySnapshot? { viewModel.snapshot }

    private var statCards: some View {
        HStack(spacing: 14) {
            gaugeCard(
                title: "Тиск пам'яті",
                subtitle: pressureLabel,
                value: pressurePercent,
                color: snapshot.map { Theme.Colors.pressure($0.pressure) } ?? Theme.Colors.success
            )
            gaugeCard(
                title: "Пам'ять",
                subtitle: snapshot.map { "\($0.used.formattedBytes) / \($0.total.formattedBytes)" } ?? "—",
                value: snapshot.map { $0.usedFraction } ?? 0,
                color: Theme.Colors.accent
            )
            gaugeCard(
                title: "Диск",
                subtitle: diskSubtitle,
                value: disk.fraction,
                color: Theme.Colors.warning
            )
        }
    }

    private func gaugeCard(title: String, subtitle: String, value: Double, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 6)
                Circle().trim(from: 0, to: max(0.001, min(1, value)))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: value)
                Text("\(Int(value * 100))%").font(Theme.Font.display(15)).foregroundStyle(Theme.Colors.textPrimary)
            }
            .frame(width: 62, height: 62)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Font.body(12)).foregroundStyle(Theme.Colors.textTertiary)
                Text(subtitle).font(Theme.Font.body(13.5, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .nimbusCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(subtitle), \(Int(value * 100)) відсотків")
    }

    private var pressureCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Пам'ять — тиск, а не «вільні гігабайти»").font(Theme.Font.body(15, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
            Text("Порожня RAM — це змарнована RAM. macOS навмисно тримає її зайнятою кешем. Ми показуємо тиск пам'яті — наскільки системі бракує ресурсу.")
                .font(Theme.Font.body(12.5)).foregroundStyle(Theme.Colors.textSecondary).lineSpacing(3)
                .padding(.top, 8)

            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Gradients.memoryScale).frame(height: 10)
                GeometryReader { geo in
                    Capsule().fill(.white).frame(width: 3, height: 16)
                        .offset(x: geo.size.width * pressurePercent - 1.5, y: -3)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                }.frame(height: 10)
            }
            .padding(.top, 16)
            HStack {
                Text("Норма"); Spacer(); Text("Помірний"); Spacer(); Text("Високий")
            }.font(Theme.Font.body(10.5)).foregroundStyle(Theme.Colors.textTertiary).padding(.top, 6)

            Text("НАЙБІЛЬШІ СПОЖИВАЧІ ПАМ'ЯТІ").font(Theme.Font.body(11, .semibold)).tracking(0.7)
                .foregroundStyle(Theme.Colors.textQuaternary).padding(.top, 22).padding(.bottom, 10)

            VStack(spacing: 3) {
                ForEach(viewModel.topConsumers) { proc in
                    HStack(spacing: 12) {
                        Text(proc.name).font(Theme.Font.body(13, .medium)).foregroundStyle(Theme.Colors.textBright).lineLimit(1)
                        Spacer()
                        Text(proc.residentBytes.formattedBytes).font(Theme.Font.mono(12)).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.vertical, 8).padding(.horizontal, 8)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nimbusCard()
    }

    // MARK: Derived

    private var pressurePercent: Double {
        guard let s = snapshot else { return 0 }
        switch s.pressure {
        case .normal: return 0.34
        case .warning: return 0.66
        case .critical: return 0.9
        }
    }
    private var pressureLabel: String {
        switch snapshot?.pressure {
        case .warning: return "Помірний"
        case .critical: return "Високий"
        default: return "Норма"
        }
    }

    private var disk: (fraction: Double, used: Int64, total: Int64) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let vals = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let total = Int64(vals?.volumeTotalCapacity ?? 0)
        let avail = vals?.volumeAvailableCapacityForImportantUsage ?? 0
        let used = max(0, total - Int64(avail))
        return (total > 0 ? Double(used) / Double(total) : 0, used, total)
    }
    private var diskSubtitle: String {
        disk.total > 0 ? "\(disk.used.formattedBytes) зайнято" : "—"
    }
}
