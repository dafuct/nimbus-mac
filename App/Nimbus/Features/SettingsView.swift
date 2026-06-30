import SwiftUI
import NimbusViewModels

/// Settings — General (incl. language), Scan & Safety, and the user exclusion
/// list. Localized via `loc`; the language picker switches UK/EN instantly.
struct SettingsView: View {
    @Environment(Localizer.self) private var loc
    @Bindable var viewModel: SettingsViewModel
    var onReplayOnboarding: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                generalCard
                scanSafetyCard
                exclusionsCard
                onboardingCard
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .padding(EdgeInsets(top: 26, leading: 28, bottom: 40, trailing: 28))
        }
        .background(Theme.Colors.window)
    }

    // MARK: General

    private var generalCard: some View {
        SettingsCard(title: loc("Загальне")) {
            ToggleRow(title: loc("Компаньйон у menu bar"),
                      subtitle: loc("Живий індикатор стану та швидке сканування з рядка меню."),
                      isOn: $viewModel.menuBarEnabled)
            Divider().overlay(Theme.Colors.hairlineSoft)
            ToggleRow(title: loc("Запускати під час входу"),
                      subtitle: loc("Nimbus стартує разом із системою (фоново, без вікна)."),
                      isOn: $viewModel.launchAtLogin)
            Divider().overlay(Theme.Colors.hairlineSoft)
            HStack {
                SettingLabel(title: loc("Мова"), subtitle: loc("Інтерфейс перемикається миттєво."))
                Spacer()
                Picker("", selection: Binding(get: { loc.language }, set: { loc.language = $0 })) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            .padding(.horizontal, 20).padding(.vertical, 13)
        }
    }

    // MARK: Scan & safety

    private var scanSafetyCard: some View {
        SettingsCard(title: loc("Сканування й безпека")) {
            ToggleRow(title: loc("Безпечне видалення (у Кошик)"),
                      subtitle: loc("Усе видалене спершу йде в Кошик. Вимкнення дозволяє остаточне видалення — обережно."),
                      isOn: $viewModel.safeDelete)
            Divider().overlay(Theme.Colors.hairlineSoft)
            ToggleRow(title: loc("Сканувати поштові вкладення"),
                      subtitle: loc("Вимкнено за замовчуванням — це ваші особисті дані."),
                      isOn: $viewModel.scanMail)
            Divider().overlay(Theme.Colors.hairlineSoft)
            HStack {
                SettingLabel(title: loc("Глибина пошуку дублікатів"),
                             subtitle: loc("«Глибоко» порівнює вміст байт у байт — повільніше, але точніше."))
                Spacer()
                Picker("", selection: $viewModel.duplicateDepth) {
                    Text(loc("Швидко")).tag(SettingsViewModel.DuplicateDepth.fast)
                    Text(loc("Звичайно")).tag(SettingsViewModel.DuplicateDepth.normal)
                    Text(loc("Глибоко")).tag(SettingsViewModel.DuplicateDepth.deep)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            .padding(.horizontal, 20).padding(.vertical, 13)
            Divider().overlay(Theme.Colors.hairlineSoft)
            modulesBlock
        }
    }

    private var modulesBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(loc("Які модулі включати у Smart Scan"))
                .font(Theme.Font.body(12)).foregroundStyle(Theme.Colors.textSecondary)
                .padding(.bottom, 6)
            CompactToggle(title: loc("Системний мотлох"), isOn: $viewModel.moduleCleanup)
            CompactToggle(title: loc("Space Lens"), isOn: $viewModel.moduleLens)
            CompactToggle(title: loc("Дублікати та фото"), isOn: $viewModel.moduleDuplicates)
            CompactToggle(title: loc("Застосунки"), isOn: $viewModel.moduleUninstaller)
            CompactToggle(title: loc("Обслуговування"), isOn: $viewModel.modulePerformance)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: Exclusions

    private var exclusionsCard: some View {
        SettingsCard(title: loc("Список винятків")) {
            Text(loc("Файли, теки та застосунки тут Nimbus ніколи не торкається — навіть під час Smart Scan."))
                .font(Theme.Font.body(12.5)).foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, 20).padding(.bottom, 12)
            VStack(spacing: 8) {
                ForEach(viewModel.exclusions, id: \.self) { path in
                    ExclusionRow(path: path) { viewModel.removeExclusion(path) }
                }
                HStack(spacing: 9) {
                    TextField(loc("Перетягніть або введіть шлях…"), text: $viewModel.newExclusionInput)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.body(12.5))
                        .padding(9)
                        .background(Theme.Colors.surfaceFaint, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
                        .onSubmit { viewModel.addExclusion() }
                    Button(loc("Додати")) { viewModel.addExclusion() }
                        .buttonStyle(.plain)
                        .font(Theme.Font.body(13, .semibold)).foregroundStyle(Theme.Colors.accentLighter)
                        .padding(.vertical, 9).padding(.horizontal, 18)
                        .background(Theme.Colors.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 14)
        }
    }

    private var onboardingCard: some View {
        HStack {
            SettingLabel(title: loc("Знайомство з Nimbus"), subtitle: loc("Переглянути привітання й пояснення дозволів знову."))
            Spacer()
            Button(loc("Показати онбординг")) { onReplayOnboarding() }
                .buttonStyle(.plain)
                .font(Theme.Font.body(13, .semibold)).foregroundStyle(Theme.Colors.textControl)
                .padding(.vertical, 9).padding(.horizontal, 16)
                .background(Theme.Colors.surfaceFaint, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
        }
        .padding(16)
        .nimbusCard()
    }
}

// MARK: - Reusable settings components (render already-localized strings verbatim)

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(Theme.Font.body(11, .semibold)).tracking(0.7)
                .foregroundStyle(Theme.Colors.textQuaternary)
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 10)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nimbusCard()
    }
}

private struct SettingLabel: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.Font.body(13.5, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
            Text(subtitle).font(Theme.Font.body(12)).foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 14) {
            SettingLabel(title: title, subtitle: subtitle)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(Theme.Colors.accent)
        }
        .padding(.horizontal, 20).padding(.vertical, 13)
    }
}

private struct CompactToggle: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            Text(title).font(Theme.Font.body(13)).foregroundStyle(Theme.Colors.textBright)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(Theme.Colors.accent)
        }
        .padding(.vertical, 5)
    }
}

private struct ExclusionRow: View {
    @Environment(Localizer.self) private var loc
    let path: String
    let onRemove: () -> Void
    var body: some View {
        HStack(spacing: 11) {
            Text(loc("ШЛЯХ")).font(Theme.Font.body(9.5, .semibold))
                .foregroundStyle(Theme.Colors.accentLight)
                .padding(.vertical, 2).padding(.horizontal, 8)
                .background(Theme.Colors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            Text(path).font(Theme.Font.mono(12.5)).foregroundStyle(Theme.Colors.textBright)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(10)
        .background(Theme.Colors.surfaceFaint, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
    }
}
