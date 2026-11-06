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
    let verdict: Verdict

    /// A chapter-title line plus the judgement itself.
    struct Verdict {
        let title: String
        let text: String
    }

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
            incomeCount: incomeCount,
            hasNamedNotes: hasNamedNotes,
            net: net,
            savingsRate: savingsRate,
            expenseItems: expenseItems,
            incomeItems: incomeItems,
            biggestExpense: biggestExpense,
            biggestDay: biggestDay,
            averageExpense: averageExpense,
            spendingDays: spendingDays,
            noSpendDays: noSpendDays,
            timePeak: timePeak,
            denominationPeak: denominationPeak,
            noteTotal: noteTotal
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

    /// The month reads like a chapter: a couplet title, then the judgement.
    /// Rules run from hard facts to softer texture, so the strongest true
    /// statement about the month always wins.
    private static func verdict(
        expenseTotal: Int,
        incomeTotal: Int,
        expenseCount: Int,
        incomeCount: Int,
        hasNamedNotes: Bool,
        net: Int,
        savingsRate: Double?,
        expenseItems: [RankedItem],
        incomeItems: [RankedItem],
        biggestExpense: Bill?,
        biggestDay: DayPeak?,
        averageExpense: Int,
        spendingDays: Int,
        noSpendDays: Int,
        timePeak: TimePeak?,
        denominationPeak: DenominationPeak?,
        noteTotal: Int
    ) -> Verdict {
        func make(_ title: String, _ text: String) -> Verdict {
            Verdict(title: title, text: text)
        }

        let topExpense = expenseItems.first
        let namedExpense: RankedItem? = topExpense.flatMap { $0.label.hasPrefix("未备注") ? nil : $0 }
        let namedIncome: RankedItem? = incomeItems.first.flatMap { $0.label.hasPrefix("未备注") ? nil : $0 }
        let rate = savingsRate ?? 0

        // MARK: Nothing on the ledger
        if expenseTotal == 0 && incomeTotal == 0 {
            return make(
                "白纸一张，账册未开",
                "这个月还没有一笔账。钱没动，故事也没开始——先记下第一笔，判词才有下文。"
            )
        }
        if expenseTotal == 0 {
            return make(
                "有进无出，守财有道",
                "本月进账 \(Formats.currencySymbol)\(Formats.money(incomeTotal))，一笔未花。钱在账上原封不动，像是替下个月留的伏笔。"
            )
        }

        // MARK: No income
        if incomeTotal == 0 {
            if hasNamedNotes, let top = namedExpense, top.share >= 0.5 {
                return make(
                    "无源之水，一注而竭",
                    "没有进项，\(expenseCount) 笔支出全靠存量，其中「\(top.label)」就占了 \(percent(top.share))。水无源头，再省也只见少。"
                )
            }
            if expenseCount >= 8 {
                return make(
                    "只出不进，坐吃山空",
                    "没有收入记录，\(expenseCount) 笔支出共 \(Formats.currencySymbol)\(Formats.money(expenseTotal))，全从存量里出。账面只见出，不见进。"
                )
            }
            return make(
                "无源之水，日渐其涸",
                "没有收入记录，\(expenseCount) 笔支出全从存量里出，合计 \(Formats.currencySymbol)\(Formats.money(expenseTotal))。水不添，总会见底。"
            )
        }

        // MARK: Overspent
        if net < 0 {
            let overspend = Double(-net) / Double(incomeTotal)
            if overspend >= 0.5 {
                return make(
                    "寅吃卯粮，库府见底",
                    "支出比收入多 \(Formats.currencySymbol)\(Formats.money(-net))，超支 \(percent(overspend))。这一月不只花光进项，还动了老本。"
                )
            }
            if overspend >= 0.2 {
                return make(
                    "入不敷出，囊中渐空",
                    "支出比收入多 \(Formats.currencySymbol)\(Formats.money(-net))，超支 \(percent(overspend))。进项追不上花销，缺口已经明明白白写在账上。"
                )
            }
            return make(
                "略有亏空，尚可回旋",
                "支出比收入多 \(Formats.currencySymbol)\(Formats.money(-net))，超支 \(percent(overspend))。窟窿不大，下月收紧一点便补得回来。"
            )
        }

        // MARK: Exactly break-even
        if net == 0 {
            return make(
                "收支相抵，两袖清风",
                "收入 \(Formats.currencySymbol)\(Formats.money(incomeTotal)) 刚够支出，一分未剩。账很干净，钱包也是。"
            )
        }

        // MARK: Income has one pillar
        if let top = namedIncome, incomeCount >= 2, top.share >= 0.75 {
            return make(
                "独木擎梁，财源一脉",
                "收入 \(Formats.currencySymbol)\(Formats.money(incomeTotal))，其中「\(top.label)」一项占了 \(percent(top.share))。进项有余，来路却只有一条。"
            )
        }

        // MARK: One expense dominates
        if let top = namedExpense, top.share >= 0.6 {
            let rest = max(0, expenseCount - top.count)
            return make(
                "一枝独秀，余皆陪衬",
                "「\(top.label)」一项吃掉 \(percent(top.share))，其余 \(rest) 笔加起来也不及它。钱有明确的大头，故事只有一个主角。"
            )
        }
        if let top = namedExpense, top.share >= 0.45 {
            return make(
                "半壁江山，尽归一物",
                "「\(top.label)」占了支出的 \(percent(top.share))，几乎半壁江山。剩下的 \(max(0, expenseCount - top.count)) 笔，都是陪衬。"
            )
        }

        // MARK: One bill or one day carries the month
        if let bill = biggestExpense,
           Double(bill.cents) / Double(expenseTotal) >= 0.45 {
            let share = Double(bill.cents) / Double(expenseTotal)
            return make(
                "一掷千金，余者寥寥",
                "最大的一笔 \(Formats.currencySymbol)\(Formats.money(bill.cents))，占全月 \(percent(share))，在 \(expenseCount) 笔里一枝独重。"
            )
        }
        if let day = biggestDay, day.share >= 0.5 {
            return make(
                "一日千金，余日萧索",
                "\(DateHelp.dayTitle(day.iso))一天花掉 \(Formats.currencySymbol)\(Formats.money(day.cents))，占全月 \(percent(day.share))，共 \(day.count) 笔。这一天抵得过其余许多天。"
            )
        }
        if let day = biggestDay, day.share >= 0.35 {
            return make(
                "一日之费，半月之粮",
                "\(DateHelp.dayTitle(day.iso))一天花掉 \(Formats.currencySymbol)\(Formats.money(day.cents))，占全月 \(percent(day.share))。那天值得回看。"
            )
        }

        // MARK: Late-night spending
        if let peak = timePeak, peak.label == "深夜", peak.share >= 0.2 {
            return make(
                "夜半散财，月下空囊",
                "深夜（\(peak.range)）的支出占了 \(percent(peak.share))，共 \(Formats.currencySymbol)\(Formats.money(peak.cents))。夜深人静时的手，往往比白天松。"
            )
        }

        // MARK: Sparse ledger
        if expenseCount <= 3 {
            return make(
                "寥寥数笔，落笔如金",
                "全月只有 \(expenseCount) 笔支出，共 \(Formats.currencySymbol)\(Formats.money(expenseTotal))。账册很薄，每一笔都记得清楚。"
            )
        }
        if noSpendDays >= 15 {
            return make(
                "半月未动，账册生尘",
                "这一月只有 \(spendingDays) 天有支出，其余 \(noSpendDays) 天账册未动。钱花得克制，日子过得清淡。"
            )
        }

        // MARK: Daily rhythm
        if spendingDays >= 20 && expenseCount >= 20 {
            return make(
                "日日有账，滴水穿石",
                "\(spendingDays) 天里落笔 \(expenseCount) 次，几乎日日有账，均笔 \(Formats.currencySymbol)\(Formats.money(averageExpense))。单看不多，合起来便是整月的开销。"
            )
        }

        // MARK: Texture
        if averageExpense < 3000 && expenseCount >= 5 {
            return make(
                "细流涓涓，汇作江河",
                "没有大额支出，\(expenseCount) 笔的平均只有 \(Formats.currencySymbol)\(Formats.money(averageExpense))。钱不是被谁拿走的，是顺着指缝一点点流走的。"
            )
        }
        if averageExpense < 5000 && expenseCount >= 3 {
            return make(
                "零碎渐多，积沙成塔",
                "最大一笔不过 \(Formats.currencySymbol)\(Formats.money(biggestExpense?.cents ?? 0))，可 \(expenseCount) 笔零碎加起来也有 \(Formats.currencySymbol)\(Formats.money(expenseTotal))。单笔不疼，合计不少。"
            )
        }
        if averageExpense >= 100_000 && expenseCount >= 3 {
            return make(
                "大手落笔，不拘细流",
                "\(expenseCount) 笔支出，均笔 \(Formats.currencySymbol)\(Formats.money(averageExpense))，最重的一笔 \(Formats.currencySymbol)\(Formats.money(biggestExpense?.cents ?? 0))。这一月的钱，落笔都重。"
            )
        }
        if let peak = denominationPeak, peak.name == "100元", peak.count >= 20 {
            return make(
                "大钞出入，手笔不凡",
                "现钞里 100 元最多，共 \(peak.count) 张。这一月的钱，进出都带着分量。"
            )
        }

        // MARK: Savings rate
        if rate >= 0.7 {
            return make(
                "仓廪充实，未雨绸缪",
                "收入 \(Formats.currencySymbol)\(Formats.money(incomeTotal))，支出 \(Formats.currencySymbol)\(Formats.money(expenseTotal))，结余率 \(percent(rate))。钱守住了，还留出了余量。"
            )
        }
        if rate >= 0.5 {
            return make(
                "收支有余，家道渐丰",
                "收入稳稳盖住支出，结余率 \(percent(rate))。这一月守得住，也攒得下。"
            )
        }
        if rate >= 0.3 {
            return make(
                "略有盈余，尚称安稳",
                "收支相抵之后还剩 \(Formats.currencySymbol)\(Formats.money(net))，结余率 \(percent(rate))。不算宽裕，日子安稳。"
            )
        }
        if rate >= 0.15 {
            return make(
                "所余无几，聊以自慰",
                "进项减去花销只剩 \(Formats.currencySymbol)\(Formats.money(net))，结余率 \(percent(rate))。钱没花光，也没留下多少。"
            )
        }
        if noteTotal == 0 {
            return make(
                "账有其实，事无其名",
                "收入几乎被支出吃尽，结余率只有 \(percent(rate))。\(expenseCount) 笔皆无备注，数字都在，故事缺席。"
            )
        }
        return make(
            "钱来钱去，不留痕迹",
            "收入几乎被支出吃尽，结余率只有 \(percent(rate))。没有明显的窟窿，也没有留下什么。"
        )
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
            in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }

    private func flowColumn(cents: Int, meta: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(Formats.currencySymbol)\(Formats.money(cents))")
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
        return "每 100 元收入，花掉 \(Formats.currencySymbol)\(Formats.money(Int((perHundred * 100).rounded())))"
    }

    private var netLabel: String {
        if analysis.incomeTotal == 0 { return "净流出" }
        return analysis.net >= 0 ? "净结余" : "缺口"
    }

    private var signedNet: String {
        let prefix = analysis.net >= 0 ? "+" : "−"
        return "\(prefix)\(Formats.currencySymbol)\(Formats.money(analysis.net))"
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
                    Text("还有 \(rest.count) 项收入，共 \(Formats.currencySymbol)\(Formats.money(restTotal))")
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
                    Text("还有 \(rest.count) 项支出，共 \(Formats.currencySymbol)\(Formats.money(restTotal))")
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
            + Text("\(Formats.currencySymbol)\(Formats.money(analysis.dailyAverage))").foregroundColor(palette.ink).fontWeight(.semibold)
            + Text("，平均一笔 ").foregroundColor(palette.muted)
            + Text("\(Formats.currencySymbol)\(Formats.money(analysis.averageExpense))").foregroundColor(palette.ink).fontWeight(.semibold)
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
                + Text("\(Formats.currencySymbol)\(Formats.money(peak.cents))").foregroundColor(palette.ink).fontWeight(.semibold)
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
                Text("\(Formats.currencySymbol)\(Formats.money(item.cents))")
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
            in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
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
        guard let bill = analysis.biggestExpense else { return "\(Formats.currencySymbol)0.00" }
        return "\(Formats.currencySymbol)\(Formats.money(bill.cents))"
    }

    private var biggestExpenseDetail: String {
        guard let bill = analysis.biggestExpense else { return "没有支出" }
        return "\(MonthAnalysis.displayNote(bill)) · \(DateHelp.dayTitle(bill.iso))"
    }

    private var biggestDayValue: String {
        guard let day = analysis.biggestDay else { return "\(Formats.currencySymbol)0.00" }
        return "\(Formats.currencySymbol)\(Formats.money(day.cents))"
    }

    private var biggestDayDetail: String {
        guard let day = analysis.biggestDay else { return "没有支出" }
        return "\(DateHelp.dayTitle(day.iso)) · \(day.count) 笔"
    }

    private var noSpendDetail: String {
        if analysis.noSpendDays > 0 {
            return "另有 \(analysis.noSpendDays) 天没花钱"
        }
        return "日均 \(Formats.currencySymbol)\(Formats.money(analysis.dailyAverage))"
    }

    private var denominationDetail: String {
        guard let peak = analysis.denominationPeak else { return "没有现钞记录" }
        return "\(peak.name)最多，\(peak.count) 张"
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


/// The month's judgement, shown first in the plaza analysis.
struct MonthVerdictCard: View {
    let analysis: MonthAnalysis
    let palette: AppPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "quote.opening")
                    .scalableFont(10, weight: .bold)
                Text("本月判词")
                    .scalableFont(9.5, weight: .semibold)
                    .tracking(0.8)
            }
            .foregroundStyle(palette.accent)

            Text(analysis.verdict.title)
                .scalableSerif(21, weight: .semibold)
                .tracking(1.6)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(analysis.verdict.text)
                .scalableFont(14, weight: .regular)
                .foregroundStyle(palette.ink2)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            palette.accentSoft,
            in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .stroke(palette.accent.opacity(0.26), lineWidth: 1)
        )
    }
}
