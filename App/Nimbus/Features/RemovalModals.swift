import SwiftUI
import NimbusKit

/// Shared "freed space" celebration overlay shown after a removal completes.
/// Skinned to `Nimbus.dc.html`'s done modal. Reusable across Cleanup / Duplicates
/// / Uninstaller.
struct RemovalDoneOverlay: View {
    let reclaimedBytes: Int64
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color(hex: 0x08080A).opacity(0.55).ignoresSafeArea()
                .onTapGesture { onClose() }
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [Theme.Colors.success.opacity(0.3), .clear],
                                                 center: .center, startRadius: 0, endRadius: 42))
                        .frame(width: 84, height: 84)
                    Circle().fill(LinearGradient(colors: [Color(hex: 0x5FE6B0), Color(hex: 0x3BBD8A)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 64, height: 64)
                        .overlay(Image(systemName: "checkmark").font(.system(size: 28, weight: .bold)).foregroundStyle(.white))
                        .shadow(color: Theme.Colors.success.opacity(0.6), radius: 14, y: 8)
                }
                .padding(.bottom, 20)
                Text("Вивільнено \(reclaimedBytes.formattedBytes)")
                    .font(Theme.Font.display(28)).foregroundStyle(Theme.Colors.textPrimary)
                Text("Файли у Кошику — можна відновити будь-коли. Очистіть Кошик, щоб остаточно повернути місце.")
                    .font(Theme.Font.body(13.5)).foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center).lineSpacing(2).padding(.top, 9)
                Button("Готово") { onClose() }
                    .buttonStyle(.plain)
                    .font(Theme.Font.body(14, .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.Gradients.accentButton, in: RoundedRectangle(cornerRadius: 11))
                    .padding(.top, 24)
            }
            .frame(width: 380)
            .padding(38)
            .background(LinearGradient(colors: [Color(hex: 0x222229), Color(hex: 0x1A1A20)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.6), radius: 40, y: 20)
        }
    }
}
