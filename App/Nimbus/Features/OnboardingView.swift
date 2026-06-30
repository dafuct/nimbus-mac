import SwiftUI
import AppKit

/// First-run onboarding overlay: welcome → three promises → Full Disk Access.
/// Skinned to `Nimbus.dc.html`. `step` is `nil` once dismissed (and persisted).
struct OnboardingView: View {
    @Binding var step: Int?
    @State private var fdaGranted = false

    private let onboardedKey = "nimbus_onboarded"

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x211D33), Color(hex: 0x121117), Color(hex: 0x0D0D11)],
                           center: .top, startRadius: 0, endRadius: 700)
                .ignoresSafeArea()
            switch step {
            case 0: welcome
            case 1: promises
            default: fda
            }
        }
        .transition(.opacity)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 0) {
            orb.padding(.bottom, 30)
            Text("Вітаємо в Nimbus").font(Theme.Font.display(38)).foregroundStyle(Theme.Colors.textPrimary)
            Text("Спокійний догляд за вашим Mac. Більше вільного місця й менше турбот — без жодних трюків і страшилок.")
                .font(Theme.Font.body(16)).foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 440).lineSpacing(3).padding(.top, 14)
            Button("Почати") { withAnimation { step = 1 } }
                .buttonStyle(.plain).modifier(BigPrimary()).padding(.top, 34)
            Button("Пропустити налаштування") { finish() }
                .buttonStyle(.plain).font(Theme.Font.body(13, .medium)).foregroundStyle(Theme.Colors.textTertiary).padding(.top, 14)
        }
        .padding(40)
    }

    private var promises: some View {
        VStack(spacing: 0) {
            Text("Три обіцянки Nimbus").font(Theme.Font.display(30)).foregroundStyle(Theme.Colors.textPrimary)
            Text("Чому вашій системі з нами безпечно").font(Theme.Font.body(14)).foregroundStyle(Theme.Colors.textSecondary).padding(.top, 10)
            VStack(spacing: 14) {
                PromiseCard(icon: "eye", tint: Theme.Colors.accentLight,
                            title: "Перегляд перед видаленням",
                            text: "Ви завжди бачите, що саме буде прибрано. Нічого не зникає без вашого підтвердження.")
                PromiseCard(icon: "arrow.uturn.backward", tint: Theme.Colors.success,
                            title: "Усе оборотне",
                            text: "За замовчуванням файли йдуть у Кошик. Передумали — відновіть одним кліком.")
                PromiseCard(icon: "lock.shield", tint: Theme.Colors.accentLighter,
                            title: "Працює локально",
                            text: "Жодних даних не залишає ваш Mac. Сканування й хешування — повністю на пристрої.")
            }
            .frame(width: 560).padding(.top, 30)
            HStack(spacing: 12) {
                Button("Назад") { withAnimation { step = 0 } }
                    .buttonStyle(.plain).font(Theme.Font.body(14, .semibold)).foregroundStyle(Theme.Colors.textControl)
                    .padding(.vertical, 13).padding(.horizontal, 28)
                    .background(Theme.Colors.surfaceFaint, in: RoundedRectangle(cornerRadius: 12))
                Button("Далі") { withAnimation { step = 2 } }
                    .buttonStyle(.plain).modifier(BigPrimary())
            }
            .padding(.top, 30)
        }
        .padding(40)
    }

    private var fda: some View {
        VStack(spacing: 0) {
            Image(systemName: fdaGranted ? "checkmark.shield.fill" : "lock.shield")
                .font(.system(size: 44)).foregroundStyle(fdaGranted ? Theme.Colors.success : Theme.Colors.accentLight)
                .padding(.bottom, 22)
            Text("Повний доступ до диска").font(Theme.Font.display(28)).foregroundStyle(Theme.Colors.textPrimary)
            Text("Щоб знаходити кеші Пошти, Safari та інших застосунків, Nimbus потребує Повного доступу до диска. Це дозвіл системи — ви надаєте його в Системних налаштуваннях.")
                .font(Theme.Font.body(14)).foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 460).lineSpacing(3).padding(.top, 12)

            Button("Відкрити Системні налаштування") { openFDA(); fdaGranted = true }
                .buttonStyle(.plain).modifier(BigPrimary()).padding(.top, 26)

            HStack(spacing: 12) {
                Button("Зробити пізніше") { finish() }
                    .buttonStyle(.plain).font(Theme.Font.body(13, .medium)).foregroundStyle(Theme.Colors.textTertiary)
                Button("Завершити") { finish() }
                    .buttonStyle(.plain).font(Theme.Font.body(13, .semibold)).foregroundStyle(Theme.Colors.accentLight)
            }
            .padding(.top, 16)
        }
        .padding(40)
    }

    private var orb: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Theme.Colors.accent.opacity(0.3), .clear], center: .center, startRadius: 0, endRadius: 64))
                .frame(width: 128, height: 128)
            RoundedRectangle(cornerRadius: 24).fill(Theme.Gradients.logo).frame(width: 84, height: 84)
                .overlay(Circle().fill(.white.opacity(0.95)).frame(width: 30, height: 30))
                .shadow(color: Theme.Colors.accentDeep.opacity(0.7), radius: 25, y: 18)
        }
    }

    // MARK: Actions

    private func openFDA() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: onboardedKey)
        withAnimation { step = nil }
    }
}

private struct PromiseCard: View {
    let icon: String
    let tint: Color
    let title: String
    let text: String
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.Font.body(15, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                Text(text).font(Theme.Font.body(13)).foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(18)
        .background(Theme.Colors.surfaceFaint, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
    }
}

private struct BigPrimary: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Font.body(15, .semibold)).foregroundStyle(.white)
            .padding(.vertical, 14).padding(.horizontal, 40)
            .background(Theme.Gradients.accentButton, in: RoundedRectangle(cornerRadius: 13))
            .shadow(color: Theme.Colors.accentDeep.opacity(0.7), radius: 18, y: 10)
    }
}
