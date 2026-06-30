import SwiftUI
import NimbusKit // MemoryPressureLevel

// Design system extracted 1:1 from the Claude Design source `Nimbus.dc.html`.
// Everything visual flows from here, so the app can be retuned in one place.
// Fonts: the design uses Hanken Grotesk (body), Space Grotesk (display/numbers),
// JetBrains Mono (paths/sizes). Bundle those .ttf files and set
// ATSApplicationFontsPath in Info.plist; `Theme.Font` falls back gracefully.

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

enum Theme {

    enum Colors {
        // Backgrounds
        static let appBackground = Color(hex: 0x08080A)   // outer canvas
        static let window = Color(hex: 0x141417)          // main surface
        static let sidebarTop = Color(hex: 0x0F0F13)
        static let sidebarBottom = Color(hex: 0x0D0D11)

        // Cards / elevated surfaces
        static let cardTop = Color(hex: 0x1C1C22)
        static let cardBottom = Color(hex: 0x191920)
        static let surfaceFaint = Color.white.opacity(0.03)
        static let surfaceFainter = Color.white.opacity(0.025)
        static let hairline = Color.white.opacity(0.07)
        static let hairlineSoft = Color.white.opacity(0.05)

        // Accent (purple)
        static let accent = Color(hex: 0x9A7CFF)
        static let accentBright = Color(hex: 0xA98FFF)
        static let accentDeep = Color(hex: 0x7A59EC)
        static let accentDeeper = Color(hex: 0x6F4FE0)
        static let accentLight = Color(hex: 0xB59BFF)
        static let accentLighter = Color(hex: 0xC9B8FF)
        static let accentBorder = Color(hex: 0x8A6CF0)

        // Status
        static let success = Color(hex: 0x4FD6A0)
        static let warning = Color(hex: 0xF5C451)
        static let danger = Color(hex: 0xFF6B6B)

        // Text
        static let textPrimary = Color(hex: 0xF2F2F5)
        static let textBright = Color(hex: 0xDCDCE2)
        static let textSecondary = Color(hex: 0x8D8D98)
        static let textTertiary = Color(hex: 0x6E6E7A)
        static let textQuaternary = Color(hex: 0x56565F)
        static let textControl = Color(hex: 0xC5C5D0)

        // Back-compat aliases used by the first-pass feature views.
        static let surface = window
        static let surfaceElevated = Color.white.opacity(0.06)

        // Traffic lights (drawn in-sidebar, matching the mock)
        static let trafficRed = Color(hex: 0xFF5F57)
        static let trafficYellow = Color(hex: 0xFEBC2E)
        static let trafficGreen = Color(hex: 0x28C840)

        static func pressure(_ level: MemoryPressureLevel) -> Color {
            switch level {
            case .normal: return success
            case .warning: return warning
            case .critical: return danger
            }
        }

        /// Stable purple-family tile color from a key, mirroring the lens oklch ramp.
        static func treemapTile(for key: String, fraction: Double = 0.5) -> Color {
            let l = 0.40 + fraction * 0.30
            return Color(hue: (0.78 + fraction * 0.05).truncatingRemainder(dividingBy: 1),
                         saturation: 0.45, brightness: l + 0.25)
        }
    }

    enum Gradients {
        static let accentButton = LinearGradient(
            colors: [Colors.accentBright, Colors.accentDeep],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        static let logo = LinearGradient(
            colors: [Colors.accent, Colors.accentDeeper],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        static let card = LinearGradient(
            colors: [Colors.cardTop, Colors.cardBottom],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        static let sidebar = LinearGradient(
            colors: [Colors.sidebarTop, Colors.sidebarBottom],
            startPoint: .top, endPoint: .bottom)
        static let scanButton = LinearGradient(
            colors: [Color(hex: 0xA98FFF), Color(hex: 0x7A59EC), Color(hex: 0x6243D8)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        static let memoryScale = LinearGradient(
            stops: [
                .init(color: Colors.success, location: 0.0),
                .init(color: Colors.success, location: 0.5),
                .init(color: Colors.warning, location: 0.72),
                .init(color: Colors.danger, location: 1.0),
            ], startPoint: .leading, endPoint: .trailing)
    }

    enum Font {
        /// Display / large numbers — Space Grotesk, falls back to rounded system.
        static func display(_ size: CGFloat, _ weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .custom("Space Grotesk", size: size).weight(weight)
        }
        /// Body — Hanken Grotesk, falls back to system.
        static func body(_ size: CGFloat, _ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .custom("Hanken Grotesk", size: size).weight(weight)
        }
        /// Monospace — JetBrains Mono, falls back to system monospaced.
        static func mono(_ size: CGFloat, _ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .custom("JetBrains Mono", size: size).weight(weight)
        }
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let chip: CGFloat = 8
        static let control: CGFloat = 10
        static let card: CGFloat = 14
        static let window: CGFloat = 14
        static let small: CGFloat = 6
        // Back-compat aliases.
        static let sm: CGFloat = 6
        static let md: CGFloat = 12
        static let lg: CGFloat = 20
    }
}

// MARK: - Reusable surface modifiers

extension View {
    /// The standard elevated card: gradient fill + hairline border + radius.
    func nimbusCard(radius: CGFloat = Theme.Radius.card) -> some View {
        self
            .background(Theme.Gradients.card, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Theme.Colors.hairline, lineWidth: 0.5)
            )
    }

    /// The primary purple action button look.
    func nimbusPrimaryButton() -> some View {
        self
            .font(Theme.Font.body(14, .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 12).padding(.horizontal, 22)
            .background(Theme.Gradients.accentButton, in: RoundedRectangle(cornerRadius: 11))
            .shadow(color: Theme.Colors.accentDeep.opacity(0.5), radius: 12, y: 6)
    }
}
