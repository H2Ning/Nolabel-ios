import Charts
import SwiftUI

struct CashPlazaView: View {
    @Bindable var model: AppModel
    let palette: AppPalette
    let onClose: () -> Void

    private var bills: [Bill] { model.monthBills }
    private var monthTitle: String { model.monthTitle }

    private var expenseBills: [Bill] {
        bills.filter { $0.type == .expense }
    }

    private var totalCents: Int {
        expenseBills.reduce(0) { $0 + $1.cents }
    }

    private var tallies: [CashGroup] {
        var counts: [String: Int] = [:]
        for bill in expenseBills {
            let groups: [CashGroup]
            if bill.groups.isEmpty {
                groups = CashBreakdown.groups(for: bill.cents)
            } else {
                groups = bill.groups.compactMap { group in
                    guard let denomination = Denomination.find(group.key) else { return nil }
                    return CashGroup(denomination: denomination, count: group.count)
                }
            }
            for group in groups {
                counts[group.denomination.id, default: 0] += group.count
            }
        }
        return Denomination.all.compactMap { denomination in
            guard let count = counts[denomination.id], count > 0 else { return nil }
            return CashGroup(denomination: denomination, count: count)
        }
    }

    private var totalNotes: Int {
        CashBreakdown.totalNotes(tallies)
    }

    private var points: [PlazaDay] {
        let calendar = Calendar.current
        let dates = expenseBills.compactMap { DateHelp.date(from: $0.iso) }
        guard let first = dates.min(), let last = dates.max() else { return [] }

        var daily: [Date: Int] = [:]
        for bill in expenseBills {
            guard let date = DateHelp.date(from: bill.iso) else { continue }
            daily[calendar.startOfDay(for: date), default: 0] += bill.cents
        }

        let start = calendar.startOfDay(for: first)
        let end = calendar.startOfDay(for: last)
        var result: [PlazaDay] = []
        var cumulative = 0
        var day = start
        while day <= end {
            let value = daily[day] ?? 0
            cumulative += value
            let components = calendar.dateComponents([.month, .day], from: day)
            result.append(PlazaDay(
                date: day,
                label: "\(components.month ?? 0)/\(components.day ?? 0)",
                daily: Double(value) / 100,
                cumulative: Double(cumulative) / 100
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    private var chartMax: Double {
        let maximum = points.map { max($0.daily, $0.cumulative) }.max() ?? 0
        guard maximum > 0 else { return 100 }
        let rough = maximum / 4
        let magnitude = pow(10, floor(log10(rough)))
        let step = max(1, ceil(rough / magnitude) * magnitude)
        return ceil(maximum / step) * step
    }

    private var tickLabels: [String] {
        let stride = max(1, Int(ceil(Double(points.count) / 6.0)))
        return points.enumerated().compactMap { index, point in
            index % stride == 0 ? point.label : nil
        }
    }

    var body: some View {
        ZStack {
            palette.pageBG.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    stage
                    chartCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.ink2)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .glassCircle()
            .accessibilityLabel("关闭现金广场")

            VStack(alignment: .leading, spacing: 5) {
                Text("现金广场")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(palette.ink)
                Text("\(monthTitle) · \(expenseBills.count) 笔 · \(totalNotes) 张现钞")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stage: some View {
        Group {
            if tallies.isEmpty {
                emptyStage
            } else {
                CashStageView(
                    source: .groups(tallies),
                    palette: palette,
                    yaw: $model.cashYaw,
                    pitch: $model.cashPitch,
                    mode: model.cashMode,
                    onCycle: { model.cycleCashMode() },
                    onReady: {}
                )
                .frame(height: 360)
            }
        }
    }

    private var emptyStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.stage,
                            palette.isDark ? Color(hex: 0x0B1510) : Color(hex: 0xDCE7DF)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Canvas { context, size in
                let step: CGFloat = 34
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                context.stroke(path, with: .color(palette.stageGrid), lineWidth: 0.6)
            }
            .allowsHitTesting(false)

            Text("这个月还没有支出")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.muted)
        }
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("每日支出与累计支出")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text("¥\(Formats.money(totalCents))")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .tracking(-0.5)
                        .monospacedDigit()
                        .foregroundStyle(palette.ink)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    legend(color: palette.expense.opacity(0.55), text: "每日支出", isLine: false)
                    legend(color: palette.accent, text: "累计支出", isLine: true)
                }
            }

            if points.isEmpty {
                Text("暂无支出")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
            } else {
                Chart(points) { point in
                    dailyBar(point)

                    LineMark(
                        x: .value("日期", point.label),
                        y: .value("累计支出", point.cumulative)
                    )
                    .foregroundStyle(palette.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("日期", point.label),
                        y: .value("累计支出", point.cumulative)
                    )
                    .foregroundStyle(palette.accent)
                    .symbolSize(18)
                }
                .chartYScale(domain: 0...chartMax)
                .chartXAxis {
                    AxisMarks(values: tickLabels) { _ in
                        AxisGridLine().foregroundStyle(palette.line.opacity(0.4))
                        AxisTick().foregroundStyle(palette.line)
                        AxisValueLabel()
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(palette.muted)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(palette.line.opacity(0.35))
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text("¥\(Int(amount))")
                                    .font(.system(size: 9, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.muted)
                            }
                        }
                    }
                }
                .frame(height: 190)
                .animation(AppMotion.grace, value: points.count)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }

    @ChartContentBuilder
    private func dailyBar(_ point: PlazaDay) -> some ChartContent {
        if points.count <= 6 {
            BarMark(
                x: .value("日期", point.label),
                y: .value("每日支出", point.daily),
                width: .fixed(22)
            )
            .foregroundStyle(palette.expense.opacity(0.55))
            .cornerRadius(2)
        } else {
            BarMark(
                x: .value("日期", point.label),
                y: .value("每日支出", point.daily),
                width: .ratio(0.55)
            )
            .foregroundStyle(palette.expense.opacity(0.55))
            .cornerRadius(2)
        }
    }

    private func legend(color: Color, text: String, isLine: Bool) -> some View {
        HStack(spacing: 6) {
            if isLine {
                Capsule()
                    .fill(color)
                    .frame(width: 14, height: 2.5)
            } else {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 9, height: 9)
            }
            Text(text)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(palette.muted)
        }
    }
}

private struct PlazaDay: Identifiable {
    let date: Date
    let label: String
    let daily: Double
    let cumulative: Double
    var id: Date { date }
}
