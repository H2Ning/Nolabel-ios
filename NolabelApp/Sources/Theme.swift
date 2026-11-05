import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "浅色"
        case .dark: "深色"
        case .system: "跟随系统"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

struct AppPalette {
    let isDark: Bool
    let pageBG: Color
    let bg: Color
    let surface: Color
    let surface2: Color
    let ink: Color
    let ink2: Color
    let muted: Color
    let faint: Color
    let line: Color
    let lineStrong: Color
    let accent: Color
    let accentSoft: Color
    let accentInk: Color
    var expense: Color
    var income: Color
    let stage: Color
    let stageGrid: Color
    let glassTint: Color
    let sheetShadow: Color

    static func palette(_ scheme: ColorScheme) -> AppPalette {
        scheme == .dark ? dark : light
    }

    func withNumberColors(_ scheme: NumberColorScheme) -> AppPalette {
        var palette = self
        palette.income = scheme.incomeColor(isDark: isDark)
        palette.expense = scheme.expenseColor(isDark: isDark)
        return palette
    }

    static let dark = AppPalette(
        isDark: true,
        pageBG: Color(hex: 0x070B09),
        bg: Color(hex: 0x08110B),
        surface: Color(hex: 0x101A13),
        surface2: Color(hex: 0x17241B),
        ink: Color(hex: 0xF1F0EA),
        ink2: Color(hex: 0xC9CCC3),
        muted: Color(hex: 0x98A298),
        faint: Color(hex: 0x687268),
        line: Color(hex: 0x8C9A8D).opacity(0.28),
        lineStrong: Color(hex: 0xAAB6AC).opacity(0.42),
        accent: Color(hex: 0xECBD57),
        accentSoft: Color(hex: 0xECBD57).opacity(0.14),
        accentInk: Color(hex: 0x231C0B),
        expense: Color(hex: 0xEF6856),
        income: Color(hex: 0x72D699),
        stage: Color(hex: 0x030804),
        stageGrid: Color(hex: 0x1A2B20).opacity(0.32),
        glassTint: Color.black.opacity(0.10),
        sheetShadow: Color.black.opacity(0.55)
    )

    static let light = AppPalette(
        isDark: false,
        pageBG: Color(hex: 0xECE9DF),
        bg: Color(hex: 0xF4F5F1),
        surface: Color(hex: 0xFDFEFB),
        surface2: Color(hex: 0xE8ECE7),
        ink: Color(hex: 0x0E1910),
        ink2: Color(hex: 0x2B362D),
        muted: Color(hex: 0x4E5850),
        faint: Color(hex: 0x586059),
        line: Color(hex: 0x59665B).opacity(0.18),
        lineStrong: Color(hex: 0x59665B).opacity(0.26),
        accent: Color(hex: 0x7C5600),
        accentSoft: Color(hex: 0x7C5600).opacity(0.14),
        accentInk: Color(hex: 0xFFFDF7),
        expense: Color(hex: 0xAC1B18),
        income: Color(hex: 0x00672D),
        stage: Color(hex: 0xE3EAE4),
        stageGrid: Color(hex: 0x536459).opacity(0.16),
        glassTint: Color.white.opacity(0.20),
        sheetShadow: Color.black.opacity(0.18)
    )
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 22, tint: Color? = nil) -> some View {
        if let tint {
            self.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
        } else {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        }
    }

    @ViewBuilder
    func glassCircle(interactive: Bool = true) -> some View {
        if interactive {
            self.glassEffect(.regular.interactive(), in: .circle)
        } else {
            self.glassEffect(.regular, in: .circle)
        }
    }

    @ViewBuilder
    func glassCapsule(interactive: Bool = true, tint: Color? = nil) -> some View {
        if let tint, interactive {
            self.glassEffect(.regular.tint(tint).interactive(), in: .capsule)
        } else if let tint {
            self.glassEffect(.regular.tint(tint), in: .capsule)
        } else if interactive {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self.glassEffect(.regular, in: .capsule)
        }
    }

    func cardSurface(_ palette: AppPalette, radius: CGFloat = 26) -> some View {
        self
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(palette.line, lineWidth: 1)
            )
    }
}

enum AppMotion {
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.92)
    static let quick = Animation.spring(response: 0.24, dampingFraction: 0.94)
    static let drawer = Animation.spring(response: 0.38, dampingFraction: 0.88)
    static let grace = Animation.easeOut(duration: 0.22)
}

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
