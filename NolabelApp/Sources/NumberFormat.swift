import SwiftUI

enum IncomeFormat: String, Codable, CaseIterable, Identifiable {
    case plain
    case plus

    var id: String { rawValue }

    var label: String {
        switch self {
        case .plain: "普通"
        case .plus: "正号"
        }
    }
}

enum ExpenseFormat: String, Codable, CaseIterable, Identifiable {
    case minus
    case bracket

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minus: "负号"
        case .bracket: "括号"
        }
    }
}

enum AmountSeparator: String, Codable, CaseIterable, Identifiable {
    case thousand
    case tenThousand
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thousand: "12,345.67"
        case .tenThousand: "1\u{2002}2345.67"
        case .none: "1234567"
        }
    }

    var summaryLabel: String {
        switch self {
        case .thousand: "千位"
        case .tenThousand: "万位"
        case .none: "无分隔"
        }
    }
}

enum NumberColorScheme: String, Codable, CaseIterable, Identifiable {
    case greenRed
    case redGreen
    case cyanRed
    case redCyan

    var id: String { rawValue }

    var label: String {
        switch self {
        case .greenRed: "绿 · 红"
        case .redGreen: "红 · 绿"
        case .cyanRed: "青 · 红"
        case .redCyan: "红 · 青"
        }
    }

    var shortLabel: String {
        switch self {
        case .greenRed: "绿红"
        case .redGreen: "红绿"
        case .cyanRed: "青红"
        case .redCyan: "红青"
        }
    }

    func incomeColor(isDark: Bool) -> Color {
        switch self {
        case .greenRed:
            return Self.green(isDark: isDark)
        case .redGreen, .redCyan:
            return Self.red(isDark: isDark)
        case .cyanRed:
            return Self.cyan(isDark: isDark)
        }
    }

    func expenseColor(isDark: Bool) -> Color {
        switch self {
        case .greenRed, .cyanRed:
            return Self.red(isDark: isDark)
        case .redGreen:
            return Self.green(isDark: isDark)
        case .redCyan:
            return Self.cyan(isDark: isDark)
        }
    }

    func netTextColor(for type: BillType, isDark: Bool) -> Color {
        guard isDark else { return Color(hex: 0xFFFDF7) }
        switch (self, type) {
        case (.greenRed, .income), (.redGreen, .expense), (.cyanRed, .income), (.redCyan, .expense):
            return Color(hex: 0x0E1910)
        default:
            return Color(hex: 0xFFFDF7)
        }
    }

    private static func green(isDark: Bool) -> Color {
        Color(hex: isDark ? 0x72D699 : 0x00672D)
    }

    private static func red(isDark: Bool) -> Color {
        Color(hex: isDark ? 0xEF6856 : 0xAC1B18)
    }

    private static func cyan(isDark: Bool) -> Color {
        Color(hex: isDark ? 0x4ECDC4 : 0x00736D)
    }
}

struct NumberFormatSettings: Codable, Equatable {
    var incomeFormat: IncomeFormat = .plain
    var expenseFormat: ExpenseFormat = .minus
    var separator: AmountSeparator = .thousand
    var colorScheme: NumberColorScheme = .greenRed

    var summary: String {
        "\(separator.summaryLabel) · \(colorScheme.shortLabel)"
    }
}
