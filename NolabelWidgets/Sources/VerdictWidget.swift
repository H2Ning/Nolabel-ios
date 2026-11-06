import SwiftUI
import WidgetKit

struct VerdictEntry: TimelineEntry {
    let date: Date
    let snapshot: VerdictSnapshot?
    let isCurrentMonth: Bool
    let monthLabel: String
}

struct VerdictProvider: TimelineProvider {
    func placeholder(in context: Context) -> VerdictEntry {
        VerdictEntry(
            date: Date(),
            snapshot: .placeholder,
            isCurrentMonth: true,
            monthLabel: VerdictSnapshot.currentMonthLabel()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (VerdictEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VerdictEntry>) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? now
        let startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)
            ?? now.addingTimeInterval(6 * 3600)
        let nextRefresh = min(now.addingTimeInterval(6 * 3600), startOfNextMonth)
        completion(Timeline(entries: [makeEntry()], policy: .after(nextRefresh)))
    }

    private func makeEntry() -> VerdictEntry {
        let snapshot = VerdictSnapshot.load()
        return VerdictEntry(
            date: Date(),
            snapshot: snapshot,
            isCurrentMonth: snapshot?.monthISO == VerdictSnapshot.currentMonthISO(),
            monthLabel: VerdictSnapshot.currentMonthLabel()
        )
    }
}

struct VerdictWidgetView: View {
    let entry: VerdictEntry

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var palette: VerdictPalette {
        colorScheme == .dark ? .dark : .light
    }

    private var isTinted: Bool {
        renderingMode != .fullColor
    }

    private var hasData: Bool {
        entry.isCurrentMonth && entry.snapshot != nil
    }

    private var displayMonth: String {
        if hasData, let snapshot = entry.snapshot {
            return snapshot.monthLabel
        }
        return entry.monthLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Spacer(minLength: 5)

            if hasData, let snapshot = entry.snapshot {
                verdict(snapshot.verdictTitle)
                Spacer(minLength: 5)
                footer(snapshot)
            } else {
                emptyVerdict
                Spacer(minLength: 5)
                emptyFooter
            }
        }
        .padding(13)
        .widgetURL(VerdictSnapshot.deepLink)
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 5) {
            Image(systemName: "quote.opening")
                .font(.system(size: 8, weight: .bold))
            Text("本月判词")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.8)
            Spacer(minLength: 4)
            Text(displayMonth)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(isTinted ? Color.secondary : palette.faint)
        }
        .foregroundStyle(isTinted ? Color.primary : palette.accent)
    }

    private func verdict(_ title: String) -> some View {
        Text(title.replacingOccurrences(of: "，", with: "，\n"))
            .font(.system(size: 19, weight: .semibold, design: .serif))
            .tracking(1.2)
            .lineSpacing(2)
            .foregroundStyle(isTinted ? Color.primary : palette.ink)
            .lineLimit(2)
            .minimumScaleFactor(0.62)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyVerdict: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("账册未开")
                .font(.system(size: 19, weight: .semibold, design: .serif))
                .tracking(1.2)
                .foregroundStyle(isTinted ? Color.primary : palette.ink)
            Text("先记一笔，判词才有下文。")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(isTinted ? Color.secondary : palette.muted)
                .lineLimit(2)
        }
    }

    private func footer(_ snapshot: VerdictSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle()
                .fill(isTinted ? Color.primary.opacity(0.25) : palette.line)
                .frame(height: 0.5)
                .padding(.bottom, 3)
            Text(snapshot.amountText)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isTinted ? Color.primary : palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(snapshot.metricLabel) · \(snapshot.countLabel)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(isTinted ? Color.secondary : palette.faint)
                .lineLimit(1)
        }
    }

    private var emptyFooter: some View {
        HStack(spacing: 4) {
            Text("打开诺诺记账")
                .font(.system(size: 9.5, weight: .semibold))
            Image(systemName: "arrow.up.right")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(isTinted ? Color.primary : palette.accent)
    }
}

struct VerdictWidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Color(hex: 0x070B09)
                RadialGradient(
                    colors: [Color(hex: 0x22372A).opacity(0.65), .clear],
                    center: UnitPoint(x: 0.5, y: -0.08),
                    startRadius: 0,
                    endRadius: 230
                )
            } else {
                Color(hex: 0xECE9DF)
                RadialGradient(
                    colors: [Color.white.opacity(0.7), .clear],
                    center: UnitPoint(x: 0.5, y: -0.08),
                    startRadius: 0,
                    endRadius: 230
                )
            }
        }
    }
}

private struct VerdictPalette {
    let ink: Color
    let muted: Color
    let faint: Color
    let accent: Color
    let line: Color

    static let dark = VerdictPalette(
        ink: Color(hex: 0xF1F0EA),
        muted: Color(hex: 0x98A298),
        faint: Color(hex: 0x7A857B),
        accent: Color(hex: 0xECBD57),
        line: Color(hex: 0x8C9A8D).opacity(0.28)
    )

    static let light = VerdictPalette(
        ink: Color(hex: 0x0E1910),
        muted: Color(hex: 0x4E5850),
        faint: Color(hex: 0x586059),
        accent: Color(hex: 0x7C5600),
        line: Color(hex: 0x59665B).opacity(0.18)
    )
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct VerdictWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: VerdictSnapshot.widgetKind,
            provider: VerdictProvider()
        ) { entry in
            VerdictWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    VerdictWidgetBackground()
                }
        }
        .configurationDisplayName("本月判词")
        .description("本月账本的判词和支出。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

@main
struct NolabelWidgetBundle: WidgetBundle {
    var body: some Widget {
        VerdictWidget()
    }
}
