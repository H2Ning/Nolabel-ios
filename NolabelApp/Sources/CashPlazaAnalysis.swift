import Foundation
import SwiftUI

/// A compact, opinionated read of one month of bills.
///
/// Notes are free text, so the report groups by note instead of pretending to
/// know categories. Every number here comes from the same `Bill` values the
/// list and the cash stage already use.
struct MonthAnalysis {
    struct RankedItem: Identifiable {
        let id: String
        let label: String
        let cents: Int
        let count: Int
        let share: Double
    }

    struct DayPeak {
        let iso: String
        let cents: Int
        let count: Int
        let share: Double
    }

    struct DenominationPeak {
        let name: String
        let count: Int
    }

    struct TimePeak {
        let label: String
        let range: String
        let cents: Int
        let share: Double
    }

    let expenseTotal: Int
    let incomeTotal: Int
    let expenseCount: Int
    let incomeCount: Int
    let net: Int
    let savingsRate: Double?
    let expenseItems: [RankedItem]
    let incomeItems: [RankedItem]
    let hasNamedNotes: Bool
    let biggestExpense: Bill?
    let biggestDay: DayPeak?
    let spendingDays: Int
    let noSpendDays: Int
    let noteTotal: Int
    let denominationPeak: DenominationPeak?
    let timePeak: TimePeak?
    let averageExpense: Int
    let dailyAverage: Int
    let expensePerHundredIncome: Double?
    let verdict: String

    init(bills: [Bill], month: Date) {
        let expenses = bills.filter { $0.type == .expense && $0.cents > 0 }
        let incomes = bills.filter { $0.type == .income && $0.cents > 0 }

        let expenseTotal = expenses.reduce(0) { $0 + $1.cents }
        let incomeTotal = incomes.reduce(0) { $0 + $1.cents }
        let expenseCount = expenses.count
        let incomeCount = incomes.count
        let net = incomeTotal - expenseTotal
        let savingsRate = incomeTotal > 0 ? Double(net) / Double(incomeTotal) : nil
        let expenseItems = Self.ranked(expenses, total: expenseTotal)
        let incomeItems = Self.ranked(incomes, total: incomeTotal)
        let hasNamedNotes = expenses.contains {
            !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let biggestExpense = expenses.max { $0.cents < $1.cents }

        var daily: [String: (cents: Int, count: Int)] = [:]
        for bill in expenses {
            var entry = daily[bill.iso] ?? (0, 0)
            entry.cents += bill.cents
            entry.count += 1
            daily[bill.iso] = entry
        }
        let biggestDay = daily.max { $0.value.cents < $1.value.cents }.map {
            DayPeak(
                iso: $0.key,
                cents: $0.value.cents,
                count: $0.value.count,
                share: expenseTotal > 0 ? Double($0.value.cents) / Double(expenseTotal) : 0
            )
        }

        let spendingDays = daily.count
        let noSpendDays = max(0, Self.countedDays(in: month) - spendingDays)
        let noteTotal = expenses.reduce(0) { $0 + Self.noteCount(for: $1) }

        var denominationCounts: [String: Int] = [:]
        var denominationValues: [String: Int] = [:]
        for bill in expenses {
            for group in Self.cashGroups(for: bill) {
                denominationCounts[group.denomination.name, default: 0] += group.count
                denominationValues[group.denomination.name] = group.denomination.value
            }
        }
        let denominationPeak = denominationCounts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return (denominationValues[lhs.key] ?? 0) < (denominationValues[rhs.key] ?? 0)
        }.map {
            DenominationPeak(name: $0.key, count: $0.value)
        }

        var timeTotals: [String: Int] = [:]
        for bill in expenses {
            guard bill.time.count >= 2, let hour = Int(bill.time.prefix(2)) else { continue }
            timeTotals[Self.timeBucket(hour).label, default: 0] += bill.cents
        }
        let timePeak = timeTotals.max { $0.value < $1.value }.flatMap { entry -> TimePeak? in
            guard let bucket = Self.timeBucket(forLabel: entry.key) else { return nil }
            return TimePeak(
                label: bucket.label,
                range: bucket.range,
                cents: entry.value,
                share: expenseTotal > 0 ? Double(entry.value) / Double(expenseTotal) : 0
            )
        }

        let averageExpense = expenseCount > 0 ? expenseTotal / expenseCount : 0
        let dailyAverage = spendingDays > 0 ? expenseTotal / spendingDays : 0
        let expensePerHundredIncome = incomeTotal > 0
            ? Double(expenseTotal) / Double(incomeTotal) * 100
            : nil

        self.expenseTotal = expenseTotal
        self.incomeTotal = incomeTotal
        self.expenseCount = expenseCount
        self.incomeCount = incomeCount
        self.net = net
        self.savingsRate = savingsRate
        self.expenseItems = expenseItems
        self.incomeItems = incomeItems
        self.hasNamedNotes = hasNamedNotes
        self.biggestExpense = biggestExpense
        self.biggestDay = biggestDay
        self.spendingDays = spendingDays
        self.noSpendDays = noSpendDays
        self.noteTotal = noteTotal
        self.denominationPeak = denominationPeak
        self.timePeak = timePeak
        self.averageExpense = averageExpense
        self.dailyAverage = dailyAverage
        self.expensePerHundredIncome = expensePerHundredIncome
        self.verdict = Self.verdict(
            expenseTotal: expenseTotal,
            incomeTotal: incomeTotal,
            expenseCount: expenseCount,
            hasNamedNotes: hasNamedNotes,
            net: net,
            savingsRate: savingsRate,
            expenseItems: expenseItems,
            biggestDay: biggestDay,
            averageExpense: averageExpense
        )
    }

    static func displayNote(_ bill: Bill) -> String {
        let raw = bill.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "未备注" : raw
    }

    private static func ranked(_ bills: [Bill], total: Int) -> [RankedItem] {
        var sums: [String: (label: String, cents: Int, count: Int)] = [:]
        for bill in bills {
            let note = bill.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let key: String
            let label: String
            if note.isEmpty {
                key = "id:\(bill.id)"
                let day = DateHelp.dayTitle(bill.iso)
                label = bill.time.isEmpty ? "未备注 · \(day)" : "未备注 · \(day) \(bill.time)"
            } else {
                key = "note:\(note)"
                label = note
            }
            var entry = sums[key] ?? (label: label, cents: 0, count: 0)
            entry.cents += bill.cents
            entry.count += 1
            sums[key] = entry
        }
        return sums.map { entry in
            RankedItem(
                id: entry.key,
                label: entry.value.label,
                cents: entry.value.cents,
                count: entry.value.count,
                share: total > 0 ? Double(entry.value.cents) / Double(total) : 0
            )
        }.sorted {
            if $0.cents != $1.cents { return $0.cents > $1.cents }
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.label < $1.label
        }
    }

    private static func noteCount(for bill: Bill) -> Int {
        cashGroups(for: bill).reduce(0) { $0 + $1.count }
    }

    private static func cashGroups(for bill: Bill) -> [CashGroup] {
        if !bill.groups.isEmpty {
            return bill.groups.compactMap { group in
                guard let denomination = Denomination.find(group.key) else { return nil }
                return CashGroup(denomination: denomination, count: max(0, group.count))
            }
        }
        return CashBreakdown.groups(for: bill.cents)
    }

    private static func countedDays(in month: Date) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let currentStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        if monthStart > currentStart { return 0 }
        if calendar.isDate(monthStart, equalTo: currentStart, toGranularity: .month) {
            return calendar.component(.day, from: now)
        }
        return calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 0
    }

    private static func timeBucket(_ hour: Int) -> (label: String, range: String) {
        switch hour {
        case 5..<11: return ("早上", "5–11 点")
        case 11..<17: return ("下午", "11–17 点")
        case 17..<23: return ("晚上", "17–23 点")
        default: return ("深夜", "23–5 点")
        }
    }

    private static func timeBucket(forLabel label: String) -> (label: String, range: String)? {
        switch label {
        case "早上": return ("早上", "5–11 点")
        case "下午": return ("下午", "11–17 点")
        case "晚上": return ("晚上", "17–23 点")
        case "深夜": return ("深夜", "23–5 点")
        default: return nil
        }
    }

    private static func verdict(
        expenseTotal: Int,
        incomeTotal: Int,
        expenseCount: Int,
        hasNamedNotes: Bool,
        net: Int,
        savingsRate: Double?,
        expenseItems: [RankedItem],
        biggestDay: DayPeak?,
        averageExpense: Int
    ) -> String {
        if expenseTotal == 0 {
            return incomeTotal > 0
                ? "这个月一分没花。收入原封不动，账单干净得不像话。"
                : "这个月还没有账单。钱没动，故事也没开始。"
        }
        if incomeTotal == 0 {
            if hasNamedNotes, let top = expenseItems.first, top.share >= 0.35 {
                return "没有收入记录，支出全靠存量。「\(top.label)」一项占了 \(percent(top.share))，先把收入补上，账才看得清。"
            }
            return "没有收入记录，\(expenseCount) 笔支出全从存量里出。钱在减少，账面上却看不到进项。"
        }
        if net < 0 {
            return "支出比收入多 ¥\(Formats.money(-net))，超支 \(percent(abs(savingsRate ?? 0)))。这个月花超了，缺口已经摆在账上。"
        }
        if net == 0 {
            return "收入刚好被支出吃平，一分没剩。账很干净，钱包也是。"
        }
        if hasNamedNotes, let top = expenseItems.first, top.share >= 0.45 {
            let rest = max(0, expenseCount - top.count)
            if rest == 0 {
                return "这个月的支出几乎只有一件事：「\(top.label)」吃掉 \(percent(top.share))。"
            }
            return "「\(top.label)」一项吃掉 \(percent(top.share))，钱有明确的大头。剩下的 \(rest) 笔，都是陪衬。"
        }
        if let day = biggestDay, day.share >= 0.35 {
            return "\(DateHelp.dayTitle(day.iso))一天花掉 ¥\(Formats.money(day.cents))，占全月 \(percent(day.share))。那天值得回看。"
        }
        if let rate = savingsRate, rate >= 0.5 {
            return "收入稳稳盖住支出，结余率 \(percent(rate))。这个月守住了，没让钱溜走太多。"
        }
        if averageExpense < 5000, expenseCount >= 3 {
            return "没有大额支出，钱是被 \(expenseCount) 笔小额一点点磨掉的。单笔不疼，加起来不少。"
        }
        if let rate = savingsRate, rate < 0.2 {
            return "钱进来又出去，结余率只有 \(percent(rate))。没有明显的大头，都是日常在慢慢漏。"
        }
        return "收支还算平衡，结余率 \(percent(savingsRate ?? 0))。钱没有乱花，但也没怎么留下。"
    }

    private static func percent(_ share: Double) -> String {
        let value = share * 100
        if value >= 10 { return String(format: "%.0f%%", value) }
        if value >= 1 { return String(format: "%.1f%%", value) }
        return String(format: "%.2f%%", value)
    }
}

struct CashPlazaAnalysisView: View {
    let palette: AppPalette
    private let analysis: MonthAnalysis

    init(bills: [Bill], month: Date, palette: AppPalette) {
        self.palette = palette
        self.analysis = MonthAnalysis(bills: bills, month: month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            flowCard
            incomeSection
            expenseSection
            if analysis.expenseTotal > 0 {
                statsGrid
            }
            verdictCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var flowCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                flowColumn(
                    cents: analysis.incomeTotal,
                    meta: "\(analysis.incomeCount) 笔收入",
                    color: palette.income
                )
                Spacer(minLength: 8)
                flowColumn(
                    cents: analysis.expenseTotal,
                    meta: "\(analysis.expenseCount) 笔支出",
                    color: palette.expense
                )
            }

            VStack(spacing: 7) {
                ratioBar

                Text(ratioCaption)
                    .scalableFont(10.5, weight: .medium)
                    .foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(netLabel)
                        .scalableFont(10.5, weight: .medium)
                        .foregroundStyle(palette.muted)
                    Spacer(minLength: 8)
                    Text(signedNet)
                        .scalableFont(14, weight: .semibold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(netColor)
                    if let rateText {
                        Text(rateText)
                            .scalableFont(9.5, weight: .medium)
                            .monospacedDigit()
                            .foregroundStyle(palette.muted)
                    }
                }
            }
        }
        .padding(16)
        .background(
            palette.surface2,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }

    private func flowColumn(cents: Int, meta: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("¥\(Formats.money(cents))")
                .scalableFont(22, weight: .bold, design: .rounded)
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(meta)
                .scalableFont(10, weight: .medium)
                .foregroundStyle(palette.muted)
        }
    }

    private var ratioBar: some View {
        GeometryReader { geo in
            let total = max(1, analysis.incomeTotal + analysis.expenseTotal)
            let incomeWidth = geo.size.width * CGFloat(analysis.incomeTotal) / CGFloat(total)
            let expenseWidth = geo.size.width * CGFloat(analysis.expenseTotal) / CGFloat(total)
            HStack(spacing: 2) {
                if analysis.incomeTotal > 0 {
                    Capsule()
                        .fill(palette.income.opacity(0.78))
                        .frame(width: max(4, incomeWidth))
                }
                if analysis.expenseTotal > 0 {
                    Capsule()
                        .fill(palette.expense.opacity(0.82))
                        .frame(width: max(4, expenseWidth))
                }
            }
        }
        .frame(height: 6)
    }

    private var ratioCaption: String {
        guard let perHundred = analysis.expensePerHundredIncome else {
            return "没有收入记录，支出全从存量里来"
        }
        return "每 100 元收入，花掉 ¥\(Formats.money(Int((perHundred * 100).rounded())))"
    }

    private var netLabel: String {
        if analysis.incomeTotal == 0 { return "净流出" }
        return analysis.net >= 0 ? "净结余" : "缺口"
    }

    private var signedNet: String {
        let prefix = analysis.net >= 0 ? "+" : "−"
        return "\(prefix)¥\(Formats.money(analysis.net))"
    }

    private var netColor: Color {
        if analysis.net < 0 { return palette.expense }
        return analysis.net == 0 ? palette.ink2 : palette.income
    }

    private var rateText: String? {
        guard let rate = analysis.savingsRate else { return nil }
        return rate >= 0 ? "结余率 \(percentText(rate))" : "超支 \(percentText(-rate))"
    }

    private var incomeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("钱从哪来的", detail: "收入")
            if analysis.incomeItems.isEmpty {
                Text("这个月没有收入记录。花的是之前的存量，或者你忘了记。")
                    .scalableFont(12.5, weight: .regular)
                    .foregroundStyle(palette.muted)
                    .lineSpacing(3)
            } else {
                VStack(spacing: 13) {
                    ForEach(Array(analysis.incomeItems.prefix(3))) { item in
                        rankRow(item, color: palette.income)
                    }
                }
                if analysis.incomeItems.count > 3 {
                    let rest = analysis.incomeItems.dropFirst(3)
                    let restTotal = rest.reduce(0) { $0 + $1.cents }
                    Text("还有 \(rest.count) 项收入，共 ¥\(Formats.money(restTotal))")
                        .scalableFont(10.5, weight: .medium)
                        .foregroundStyle(palette.muted)
                }
            }
        }
    }

    private var expenseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("钱怎么没的", detail: "支出")
            if analysis.expenseItems.isEmpty {
                Text("这个月没有支出。钱还在，账单是空的。")
                    .scalableFont(12.5, weight: .regular)
                    .foregroundStyle(palette.muted)
                    .lineSpacing(3)
            } else {
                expenseSummary
                    .scalableFont(12, weight: .regular)
                    .lineSpacing(3)
                if !analysis.hasNamedNotes {
                    Text("这个月没写备注，支出按单笔列出。")
                        .scalableFont(10.5, weight: .medium)
                        .foregroundStyle(palette.muted)
                }
                VStack(spacing: 13) {
                    ForEach(Array(analysis.expenseItems.prefix(3))) { item in
                        rankRow(item, color: palette.expense)
                    }
                }
                if analysis.expenseItems.count > 3 {
                    let rest = analysis.expenseItems.dropFirst(3)
                    let restTotal = rest.reduce(0) { $0 + $1.cents }
                    Text("还有 \(rest.count) 项支出，共 ¥\(Formats.money(restTotal))")
                        .scalableFont(10.5, weight: .medium)
                        .foregroundStyle(palette.muted)
                }
                if let timePeak = analysis.timePeak {
                    timeLine(timePeak)
                }
            }
        }
    }

    private var expenseSummary: Text {
        Text("日均花费 ").foregroundColor(palette.muted)
            + Text("¥\(Formats.money(analysis.dailyAverage))").foregroundColor(palette.ink).fontWeight(.semibold)
            + Text("，平均一笔 ").foregroundColor(palette.muted)
            + Text("¥\(Formats.money(analysis.averageExpense))").foregroundColor(palette.ink).fontWeight(.semibold)
            + Text("。").foregroundColor(palette.muted)
    }

    private func timeLine(_ peak: MonthAnalysis.TimePeak) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "clock")
                .scalableFont(10, weight: .semibold)
                .foregroundStyle(palette.muted)
            (Text("钱最常在这时出门：").foregroundColor(palette.muted)
                + Text(peak.label).foregroundColor(palette.expense).fontWeight(.semibold)
                + Text("，\(peak.range)花掉 ").foregroundColor(palette.muted)
                + Text("¥\(Formats.money(peak.cents))").foregroundColor(palette.ink).fontWeight(.semibold)
                + Text("，占 \(percentText(peak.share))。").foregroundColor(palette.muted))
                .scalableFont(11, weight: .regular)
                .lineSpacing(2)
        }
    }

    private func rankRow(_ item: MonthAnalysis.RankedItem, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.label)
                    .scalableFont(13.5, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                if item.count > 1 {
                    Text("×\(item.count)")
                        .scalableFont(9.5, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(palette.muted)
                }
                Spacer(minLength: 8)
                Text("¥\(Formats.money(item.cents))")
                    .scalableFont(13, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(palette.ink2)
                Text(percentText(item.share))
                    .scalableFont(9.5, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(palette.muted)
                    .frame(width: 38, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.line.opacity(0.45))
                    Capsule()
                        .fill(color.opacity(0.72))
                        .frame(width: max(3, geo.size.width * CGFloat(item.share)))
                }
            }
            .frame(height: 4)
        }
    }

    private var statsGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                statCell(
                    label: "最大单笔",
                    value: biggestExpenseValue,
                    detail: biggestExpenseDetail
                )
                Rectangle()
                    .fill(palette.line)
                    .frame(width: 1)
                statCell(
                    label: "最狠一天",
                    value: biggestDayValue,
                    detail: biggestDayDetail
                )
            }
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
            HStack(spacing: 0) {
                statCell(
                    label: "花钱天数",
                    value: "\(analysis.spendingDays) 天",
                    detail: noSpendDetail
                )
                Rectangle()
                    .fill(palette.line)
                    .frame(width: 1)
                statCell(
                    label: "现钞",
                    value: "\(analysis.noteTotal) 张",
                    detail: denominationDetail
                )
            }
        }
        .background(
            palette.surface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }

    private func statCell(label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .scalableFont(9.5, weight: .semibold)
                .tracking(0.5)
                .foregroundStyle(palette.muted)
            Text(value)
                .scalableFont(19, weight: .bold, design: .rounded)
                .tracking(-0.4)
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(detail)
                .scalableFont(10, weight: .medium)
                .foregroundStyle(palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var biggestExpenseValue: String {
        guard let bill = analysis.biggestExpense else { return "¥0.00" }
        return "¥\(Formats.money(bill.cents))"
    }

    private var biggestExpenseDetail: String {
        guard let bill = analysis.biggestExpense else { return "没有支出" }
        return "\(MonthAnalysis.displayNote(bill)) · \(DateHelp.dayTitle(bill.iso))"
    }

    private var biggestDayValue: String {
        guard let day = analysis.biggestDay else { return "¥0.00" }
        return "¥\(Formats.money(day.cents))"
    }

    private var biggestDayDetail: String {
        guard let day = analysis.biggestDay else { return "没有支出" }
        return "\(DateHelp.dayTitle(day.iso)) · \(day.count) 笔"
    }

    private var noSpendDetail: String {
        if analysis.noSpendDays > 0 {
            return "另有 \(analysis.noSpendDays) 天没花钱"
        }
        return "日均 ¥\(Formats.money(analysis.dailyAverage))"
    }

    private var denominationDetail: String {
        guard let peak = analysis.denominationPeak else { return "没有现钞记录" }
        return "\(peak.name)最多，\(peak.count) 张"
    }

    private var verdictCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "quote.opening")
                    .scalableFont(10, weight: .bold)
                Text("本月判词")
                    .scalableFont(9.5, weight: .semibold)
                    .tracking(0.8)
            }
            .foregroundStyle(palette.accent)

            Text(analysis.verdict)
                .scalableFont(16, weight: .semibold)
                .foregroundStyle(palette.ink)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            palette.accentSoft,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.accent.opacity(0.26), lineWidth: 1)
        )
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .scalableFont(16, weight: .semibold)
                .foregroundStyle(palette.ink)
            Rectangle()
                .fill(palette.line)
                .frame(width: 1, height: 12)
            Text(detail)
                .scalableFont(11, weight: .medium)
                .foregroundStyle(palette.muted)
            Spacer(minLength: 0)
        }
    }

    private func percentText(_ share: Double) -> String {
        let value = share * 100
        if value >= 10 { return String(format: "%.0f%%", value) }
        if value >= 1 { return String(format: "%.1f%%", value) }
        return String(format: "%.2f%%", value)
    }
}
