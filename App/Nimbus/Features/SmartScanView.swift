import SwiftUI
import NimbusKit
import NimbusViewModels

/// The Smart Scan hero — the app's home. Idle shows the scan orb; running shows
/// the current stage; done shows result tiles built from the real orchestrated
/// scan (`SmartScanViewModel`). Localized via `loc`. Skinned to `Nimbus.dc.html`.
struct SmartScanView: View {
    @Environment(Localizer.self) private var loc
    @Bindable var viewModel: SmartScanViewModel
    var onOpenModule: (RootView.Module) -> Void

    var body: some View {
        ScrollView {
            switch viewModel.phase {
            case .idle: idle
            case .scanning: scanning
            case .done: done
            }
        }
        .background(Theme.Colors.window)
    }

    private var idle: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(
                    RadialGradient(colors: [Theme.Colors.accent.opacity(0.16), .clear],
                                   center: .center, startRadius: 0, endRadius: 150)
                ).frame(width: 300, height: 300)
                Circle().strokeBorder(Theme.Colors.hairline, lineWidth: 0.5).frame(width: 230, height: 230)
                Button(action: { viewModel.run() }) {
                    VStack(spacing: 2) {
                        Text(loc("Сканувати")).font(Theme.Font.display(23, .semibold)).foregroundStyle(.white)
                        Text(loc("Перевірити весь Mac")).font(Theme.Font.body(12, .medium)).foregroundStyle(.white.opacity(0.78))
                    }
                    .frame(width: 172, height: 172)
                    .background(Theme.Gradients.scanButton, in: Circle())
                    .shadow(color: Theme.Colors.accentDeep.opacity(0.65), radius: 25, y: 18)
                }
                .buttonStyle(.plain)
            }
            VStack(spacing: 10) {
                Text(loc("Готові оглянути ваш Mac")).font(Theme.Font.display(26)).foregroundStyle(Theme.Colors.textPrimary)
                Text(loc("Nimbus перевірить усі модулі й покаже, що можна безпечно прибрати. Нічого не видаляється без вашого підтвердження."))
                    .font(Theme.Font.body(14)).foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 430).lineSpacing(3)
            }
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity).padding(40)
    }

    private var scanning: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(.white.opacity(0.07), lineWidth: 6).frame(width: 180, height: 180)
                ProgressView().controlSize(.large)
            }
            VStack(spacing: 4) {
                Text(loc("Сканування…")).font(Theme.Font.display(20)).foregroundStyle(Theme.Colors.textPrimary)
                Text(loc(viewModel.currentStage)).font(Theme.Font.body(13, .semibold)).foregroundStyle(Theme.Colors.accentLight)
            }
            Button(loc("Скасувати")) { viewModel.cancel() }.buttonStyle(.plain).foregroundStyle(Theme.Colors.textControl)
        }
        .frame(maxWidth: .infinity, minHeight: 460).padding(40)
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 7) {
                        Circle().fill(Theme.Colors.success).frame(width: 6, height: 6)
                        Text(loc("Перевірку завершено")).font(Theme.Font.body(11.5, .semibold)).foregroundStyle(Theme.Colors.success)
                    }
                    .padding(.vertical, 4).padding(.horizontal, 11)
                    .background(Theme.Colors.success.opacity(0.13), in: Capsule())

                    (Text(loc("Знайдено ")).foregroundStyle(Theme.Colors.textPrimary)
                     + Text(viewModel.totalFound.formattedBytes).foregroundStyle(Theme.Colors.accentLight)
                     + Text(loc(", які можна безпечно прибрати")).foregroundStyle(Theme.Colors.textPrimary))
                        .font(Theme.Font.display(32))
                }
                Spacer()
                Button(loc("Сканувати знову")) { viewModel.run() }
                    .buttonStyle(.plain)
                    .font(Theme.Font.body(13, .semibold)).foregroundStyle(Theme.Colors.textControl)
                    .padding(.vertical, 10).padding(.horizontal, 18)
                    .background(Theme.Colors.surfaceFaint, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(tiles) { tile in
                    Button { onOpenModule(tile.module) } label: { tileCard(tile) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(EdgeInsets(top: 30, leading: 34, bottom: 40, trailing: 34))
    }

    private func tileCard(_ tile: Tile) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: tile.icon)
                    .font(.system(size: 18)).foregroundStyle(tile.accent)
                    .frame(width: 42, height: 42)
                    .background(tile.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(tile.title).font(Theme.Font.body(15, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Text(tile.metric).font(Theme.Font.display(18)).foregroundStyle(tile.metricColor)
                    }
                    Text(tile.desc).font(Theme.Font.body(12.5)).foregroundStyle(Theme.Colors.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider().overlay(Theme.Colors.hairline)
            HStack {
                Text(tile.detail).font(Theme.Font.body(12)).foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
                HStack(spacing: 5) { Text(tile.cta); Text("›") }
                    .font(Theme.Font.body(12.5, .semibold)).foregroundStyle(Theme.Colors.accentLight)
            }
        }
        .padding(18)
        .nimbusCard()
    }

    struct Tile: Identifiable {
        let id = UUID()
        let module: RootView.Module
        let icon: String
        let title: String
        let desc: String
        let detail: String
        let metric: String
        let metricColor: Color
        let accent: Color
        let cta: String
    }

    /// Tile fields are localized here (where `loc` is available); `tileCard`
    /// renders them verbatim. Sizes (formattedBytes) are already locale-correct.
    private var tiles: [Tile] {
        [
            Tile(module: .cleanup, icon: "wand.and.stars", title: loc("Системний мотлох"),
                 desc: loc("Кеші, логи, тимчасові файли — безпечні до видалення"),
                 detail: loc("%lld елементів", viewModel.cleanupItemCount), metric: viewModel.reclaimableCleanup.formattedBytes,
                 metricColor: Theme.Colors.accentLighter, accent: Theme.Colors.accent, cta: loc("Переглянути")),
            Tile(module: .lens, icon: "square.grid.2x2.fill", title: loc("Великі та старі файли"),
                 desc: loc("Мапа диску — що займає найбільше місця"),
                 detail: loc("мапа диску"), metric: loc("Огляд"),
                 metricColor: Theme.Colors.textPrimary, accent: Theme.Colors.textSecondary, cta: loc("Відкрити Space Lens")),
            Tile(module: .duplicates, icon: "doc.on.doc.fill", title: loc("Дублікати та схожі фото"),
                 desc: loc("Точні дублікати (BLAKE3) і візуально схожі фото"),
                 detail: loc("сканувати на вимогу"), metric: loc("Сканувати"),
                 metricColor: Theme.Colors.accentLighter, accent: Theme.Colors.accent, cta: loc("Переглянути")),
            Tile(module: .uninstaller, icon: "macwindow", title: loc("Застосунки"),
                 desc: loc("Видалення разом із прихованими залишками"),
                 detail: loc("%lld застосунків", viewModel.totalApps), metric: loc("%lld рідко", viewModel.rareApps),
                 metricColor: viewModel.rareApps > 0 ? Theme.Colors.warning : Theme.Colors.textPrimary,
                 accent: Theme.Colors.textSecondary, cta: loc("Переглянути")),
            Tile(module: .performance, icon: "bolt.fill", title: loc("Обслуговування"),
                 desc: loc("Рекомендовані задачі для плавнішої роботи"),
                 detail: loc("напр. переіндексація Spotlight"), metric: loc("%lld задачі", viewModel.recommendedTasks),
                 metricColor: Theme.Colors.warning, accent: Theme.Colors.warning, cta: loc("Запустити")),
            Tile(module: .health, icon: "waveform.path.ecg", title: loc("Стан системи"),
                 desc: loc("Тиск пам'яті в реальному часі"),
                 detail: loc("моніторинг у реальному часі"), metric: loc(viewModel.healthLabel),
                 metricColor: Theme.Colors.pressure(viewModel.healthPressure), accent: Theme.Colors.success, cta: loc("Деталі")),
        ]
    }
}
