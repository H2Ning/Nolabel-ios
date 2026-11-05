import Charts
import Foundation
import SwiftUI

struct CashPlazaView: View {
    @Bindable var model: AppModel
    let palette: AppPalette
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stageMode = 2
    @State private var stageYaw = Double(CashSceneLayout.defaultYaw)
    @State private var stagePitch = Double(CashSceneLayout.packageTilt)
    @State private var analysisOpen = ProcessInfo.processInfo.arguments.contains("--preview-plaza-analysis")
    @State private var analysisVisible = ProcessInfo.processInfo.arguments.contains("--preview-plaza-analysis")

    private var monthTitle: String { model.monthTitle }

    private struct PlazaSnapshot {
        let incomeCount: Int
        let expenseCount: Int
        let totalCents: Int
        let tallies: [CashGroup]
        let totalNotes: Int
        let points: [PlazaDay]
        let chartMax: Double
        let tickLabels: [String]

        init(bills: [Bill]) {
            let expenses = bills.filter { $0.type == .expense }
            incomeCount = bills.filter { $0.type == .income }.count
            expenseCount = expenses.count
            totalCents = expenses.reduce(0) { $0 + $1.cents }

            var counts: [String: Int] = [:]
            for bill in expenses {
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
            let tallies = Denomination.all.compactMap { denomination -> CashGroup? in
                guard let count = counts[denomination.id], count > 0 else { return nil }
                return CashGroup(denomination: denomination, count: count)
            }
            self.tallies = tallies
            totalNotes = CashBreakdown.totalNotes(tallies)

            let calendar = Calendar.current
            let dates = expenses.compactMap { DateHelp.date(from: $0.iso) }
            var points: [PlazaDay] = []
            if let first = dates.min(), let last = dates.max() {
                var daily: [Date: Int] = [:]
                for bill in expenses {
                    guard let date = DateHelp.date(from: bill.iso) else { continue }
                    daily[calendar.startOfDay(for: date), default: 0] += bill.cents
                }
                var cumulative = 0
                var day = calendar.startOfDay(for: first)
                let end = calendar.startOfDay(for: last)
                while day <= end {
                    let value = daily[day] ?? 0
                    cumulative += value
                    let components = calendar.dateComponents([.month, .day], from: day)
                    points.append(PlazaDay(
                        date: day,
                        label: "\(components.month ?? 0)/\(components.day ?? 0)",
                        daily: Double(value) / 100,
                        cumulative: Double(cumulative) / 100
                    ))
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                }
            }
            self.points = points

            let maximum = points.map { max($0.daily, $0.cumulative) }.max() ?? 0
            if maximum > 0 {
                let rough = maximum / 4
                let magnitude = pow(10, floor(log10(rough)))
                let step = max(1, ceil(rough / magnitude) * magnitude)
                chartMax = ceil(maximum / step) * step
            } else {
                chartMax = 100
            }

            let labelStride = max(1, Int(ceil(Double(points.count) / 6.0)))
            tickLabels = points.enumerated().compactMap { index, point in
                index % labelStride == 0 ? point.label : nil
            }
        }
    }

    var body: some View {
        content(PlazaSnapshot(bills: model.monthBills))
    }

    private func content(_ snapshot: PlazaSnapshot) -> some View {
        ZStack {
            palette.pageBG.ignoresSafeArea()

            VStack(spacing: 0) {
                header(snapshot)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 14)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            if !analysisOpen {
                                stage(snapshot)
                                    .transition(
                                        .asymmetric(
                                            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                                        )
                                    )
                            }

                            chartButton(snapshot)

                            if analysisOpen && analysisVisible {
                                VStack(spacing: 0) {
                                    CashPlazaAnalysisView(
                                        bills: model.monthBills,
                                        month: model.selectedMonth,
                                        palette: palette
                                    )
                                    .id("plazaAnalysis-\(model.monthDataVersion)")
                                }
                                .id("plazaAnalysisBottom")
                                .transition(.opacity.combined(with: .scale(scale: 0.99, anchor: .top)))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 2)
                        .padding(.bottom, 36)
                        .id("plazaTop")
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: analysisOpen) { _, _ in
                        withAnimation(reduceMotion ? nil : AppMotion.spring) {
                            proxy.scrollTo("plazaTop", anchor: .top)
                        }
                    }
                    .onAppear {
                        guard ProcessInfo.processInfo.arguments.contains("--preview-plaza-analysis-bottom") else {
                            return
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            proxy.scrollTo("plazaAnalysisBottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : AppMotion.spring, value: analysisOpen)
    }

    private func header(_ snapshot: PlazaSnapshot) -> some View {
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
                Text(analysisOpen ? "本月账单分析" : "现金广场")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(palette.ink)
                if analysisOpen {
                    analysisSubtitle(snapshot)
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                } else {
                    Text("\(monthTitle) · \(snapshot.expenseCount) 笔 · \(snapshot.totalNotes) 张现钞")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(palette.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func analysisSubtitle(_ snapshot: PlazaSnapshot) -> Text {
        Text("本月共 ")
            .foregroundColor(palette.muted)
            + Text("\(snapshot.incomeCount) 笔收入")
                .foregroundColor(palette.income)
                .fontWeight(.semibold)
            + Text("，")
                .foregroundColor(palette.muted)
            + Text("\(snapshot.expenseCount) 笔支出")
                .foregroundColor(palette.expense)
                .fontWeight(.semibold)
    }

    private func stage(_ snapshot: PlazaSnapshot) -> some View {
        Group {
            if snapshot.tallies.isEmpty {
                emptyStage
            } else {
                CashStageView(
                    source: .groups(snapshot.tallies),
                    palette: palette,
                    yaw: $stageYaw,
                    pitch: $stagePitch,
                    mode: stageMode,
                    onCycle: {
                        stageMode = stageMode % 3 + 1
                        Haptics.cashMode(stageMode)
                    },
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

    private func chartButton(_ snapshot: PlazaSnapshot) -> some View {
        Button {
            Haptics.pick()
            if analysisOpen {
                analysisVisible = false
                withAnimation(reduceMotion ? nil : AppMotion.spring) {
                    analysisOpen = false
                }
            } else {
                withAnimation(reduceMotion ? nil : AppMotion.spring) {
                    analysisOpen = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                    guard analysisOpen else { return }
                    withAnimation(reduceMotion ? nil : AppMotion.spring) {
                        analysisVisible = true
                    }
                }
            }
        } label: {
            chartCard(snapshot)
        }
        .buttonStyle(PressableStyle(scale: 0.985))
        .accessibilityLabel(
            analysisOpen
                ? "收起账单分析，返回现金广场"
                : "每日支出与累计支出，共 \(Formats.money(snapshot.totalCents)) 元"
        )
        .accessibilityHint(
            analysisOpen ? "轻点返回现金展示" : "轻点隐藏现金展示，查看本月花费分析"
        )
    }

    private func chartCard(_ snapshot: PlazaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("每日支出与累计支出")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text("¥\(Formats.money(snapshot.totalCents))")
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

            if snapshot.points.isEmpty {
                Text("暂无支出")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 124)
            } else {
                Chart(snapshot.points) { point in
                    dailyBar(point, count: snapshot.points.count)

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
                .chartYScale(domain: 0...snapshot.chartMax)
                .chartXAxis {
                    AxisMarks(values: snapshot.tickLabels) { _ in
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
                .frame(height: 124)
                .animation(AppMotion.grace, value: snapshot.points.count)
            }

            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
                .padding(.top, 2)

            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 9.5, weight: .semibold))
                Text(analysisOpen ? "收起分析，回到现金展示" : "点击图表，查看本月账单分析")
                    .font(.system(size: 10.5, weight: .medium))
                Spacer()
                Image(systemName: analysisOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(palette.muted)
            .contentShape(Rectangle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ChartContentBuilder
    private func dailyBar(_ point: PlazaDay, count: Int) -> some ChartContent {
        if count <= 6 {
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
