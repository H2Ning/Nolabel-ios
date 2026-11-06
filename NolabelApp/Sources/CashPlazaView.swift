import Charts
import Foundation
import SwiftUI

struct CashPlazaView: View {
    @Bindable var model: AppModel
    let palette: AppPalette
    @Binding var detent: PresentationDetent
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stageYaw = Double(CashSceneLayout.defaultYaw)
    @State private var stagePitch = Double(CashSceneLayout.packageTilt)
    @State private var selectedDayLabel: String?
    @State private var headerHeight: CGFloat = 0
    @State private var verdictBottom: CGFloat = 0
    @State private var chartBottom: CGFloat = 0
    @State private var expandedGridHeight: CGFloat = 0
    @State private var detentHeightUpdate = false

    private var monthTitle: String { model.monthTitle }

    /// Small shows the heading and the verdict; medium adds the chart.
    private var smallDetentHeight: CGFloat {
        guard headerHeight > 0, verdictBottom > 0 else { return 300 }
        return headerHeight + verdictBottom + 20
    }

    private var mediumDetentHeight: CGFloat {
        guard headerHeight > 0, chartBottom > 0 else { return 560 }
        return headerHeight + chartBottom + 20
    }

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

            let tickCount = min(6, points.count)
            if tickCount <= 1 {
                tickLabels = points.map(\.label)
            } else {
                tickLabels = (0..<tickCount).map { index in
                    let source = Int(
                        (Double(index) * Double(points.count - 1) / Double(tickCount - 1)).rounded()
                    )
                    return points[source].label
                }
            }
        }
    }

    var body: some View {
        content(PlazaSnapshot(bills: model.monthBills))
            .presentationDetents(
                [.height(smallDetentHeight), .height(mediumDetentHeight), .large],
                selection: $detent
            )
            .presentationDragIndicator(.visible)
    }

    private func content(_ snapshot: PlazaSnapshot) -> some View {
        ZStack {
            palette.pageBG.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 14)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        headerHeight = height
                    }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 22) {
                            analysisTitle(snapshot)

                            MonthVerdictCard(
                                analysis: MonthAnalysis(
                                    bills: model.monthBills,
                                    month: model.selectedMonth
                                ),
                                palette: palette
                            )
                            .onGeometryChange(for: CGFloat.self) { geometry in
                                geometry.frame(in: .named("plazaContent")).maxY
                            } action: { bottom in
                                if bottom.isFinite, bottom > 0 {
                                    verdictBottom = bottom
                                }
                            }

                            chartCard(snapshot)
                                .onGeometryChange(for: CGFloat.self) { geometry in
                                    geometry.frame(in: .named("plazaContent")).maxY
                                } action: { bottom in
                                    if bottom.isFinite, bottom > 0 {
                                        chartBottom = bottom
                                    }
                                }

                            VStack(spacing: 0) {
                                CashPlazaAnalysisView(
                                    bills: model.monthBills,
                                    month: model.selectedMonth,
                                    palette: palette
                                )
                                .id("plazaAnalysis-\(model.monthDataVersion)")
                            }
                            .id("plazaAnalysisBottom")

                            cashPlazaTitle(snapshot)
                            stage(snapshot)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 2)
                        .padding(.bottom, 20)
                        .id("plazaTop")
                        .coordinateSpace(name: "plazaContent")
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: detent) { _, newValue in
                        // The system sheet owns the drag; a detent change is the threshold.
                        if detentHeightUpdate {
                            detentHeightUpdate = false
                        } else {
                            Haptics.detent()
                        }
                        if newValue != .large {
                            withAnimation(reduceMotion ? nil : AppMotion.spring) {
                                proxy.scrollTo("plazaTop", anchor: .top)
                            }
                        }
                    }
                    .onChange(of: smallDetentHeight) { oldValue, newValue in
                        guard detent == .height(oldValue) else { return }
                        detentHeightUpdate = true
                        detent = .height(newValue)
                    }
                    .onChange(of: mediumDetentHeight) { oldValue, newValue in
                        guard detent == .height(oldValue) else { return }
                        detentHeightUpdate = true
                        detent = .height(newValue)
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
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .scalableFont(15, weight: .semibold)
                    .foregroundStyle(palette.ink2)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .glassCircle()
            .accessibilityLabel("关闭")

            Spacer()
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

    private func analysisTitle(_ snapshot: PlazaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("本月账单分析")
                .scalableFont(28, weight: .bold)
                .tracking(-0.5)
                .foregroundStyle(palette.ink)
            analysisSubtitle(snapshot)
                .scalableFont(12, weight: .medium)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cashPlazaTitle(_ snapshot: PlazaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("现金广场")
                .scalableFont(28, weight: .bold)
                .tracking(-0.5)
                .foregroundStyle(palette.ink)
            Text("\(monthTitle) · \(snapshot.expenseCount) 笔 · \(snapshot.totalNotes) 张现钞")
                .scalableFont(12, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stageHeight: CGFloat {
        // 展开 mode hugs the rendered notes; the 3D modes keep the stage height.
        if model.plazaStageMode == 3, expandedGridHeight > 0 {
            return expandedGridHeight
        }
        return 360
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
                    mode: model.plazaStageMode,
                    onSelectMode: { value in
                        model.plazaStageMode = value
                        Haptics.cashMode(value)
                    },
                    onReady: {},
                    onExpandedContentHeight: { height in
                        expandedGridHeight = height
                    }
                )
                .frame(height: stageHeight)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: stageHeight)
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
                .scalableFont(13, weight: .medium)
                .foregroundStyle(palette.muted)
        }
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }

    private func chartCard(_ snapshot: PlazaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("每日支出与累计支出")
                        .scalableFont(15, weight: .semibold)
                        .foregroundStyle(palette.ink)
                    Text("¥\(Formats.money(snapshot.totalCents))")
                        .scalableFont(25, weight: .bold, design: .rounded)
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

            HStack(spacing: 10) {
                if let label = selectedDayLabel,
                   let point = snapshot.points.first(where: { $0.label == label }) {
                    Text(label)
                        .foregroundStyle(palette.ink2)
                    Text("支出 ¥\(Formats.money(Int((point.daily * 100).rounded())))")
                        .foregroundStyle(palette.expense)
                    Text("累计 ¥\(Formats.money(Int((point.cumulative * 100).rounded())))")
                        .foregroundStyle(palette.accent)
                }
            }
            .scalableFont(11, weight: .medium)
            .monospacedDigit()
            .frame(height: 15, alignment: .leading)
            .opacity(selectedDayLabel == nil ? 0 : 1)

            if snapshot.points.isEmpty {
                Text("暂无支出")
                    .scalableFont(12, weight: .medium)
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
                .chartXSelection(value: $selectedDayLabel)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let label = selectedDayLabel,
                           let point = snapshot.points.first(where: { $0.label == label }),
                           let plotFrame = proxy.plotFrame,
                           let x = proxy.position(forX: label),
                           let y = proxy.position(forY: point.cumulative) {
                            let plot = geometry[plotFrame]
                            let pointX = plot.origin.x + x
                            let pointY = plot.origin.y + y
                            // Only the arms between the point and each axis.
                            Path { path in
                                path.move(to: CGPoint(x: pointX, y: pointY))
                                path.addLine(to: CGPoint(x: pointX, y: plot.maxY))
                                path.move(to: CGPoint(x: pointX, y: pointY))
                                path.addLine(to: CGPoint(x: plot.minX, y: pointY))
                            }
                            .stroke(
                                palette.accent.opacity(0.45),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                            )
                            Circle()
                                .fill(palette.accent)
                                .frame(width: 6, height: 6)
                                .position(x: pointX, y: pointY)
                        }
                    }
                }
                .chartYScale(domain: 0...snapshot.chartMax)
                .chartXAxis {
                    AxisMarks(preset: .aligned, values: snapshot.tickLabels) { value in
                        AxisGridLine().foregroundStyle(palette.line.opacity(0.4))
                        AxisTick().foregroundStyle(palette.line)
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .scalableFont(9, weight: .medium)
                                    .foregroundStyle(palette.muted)
                                    .fixedSize()
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(palette.line.opacity(0.35))
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text("¥\(Int(amount))")
                                    .scalableFont(9, weight: .medium)
                                    .monospacedDigit()
                                    .foregroundStyle(palette.muted)
                            }
                        }
                    }
                }
                .frame(height: 124)
                .animation(AppMotion.grace, value: snapshot.points.count)
                .accessibilityLabel("每日支出与累计支出图，本月共 \(Formats.money(snapshot.totalCents)) 元")
            }

        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
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
                .scalableFont(9.5, weight: .medium)
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

