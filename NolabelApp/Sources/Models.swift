import Foundation

enum BillType: String, Codable, Hashable {
    case expense
    case income

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "income", "收入", "in":
            self = .income
        default:
            self = .expense
        }
    }
}

struct BillDenomGroup: Codable, Hashable, Identifiable {
    var key: String
    var count: Int

    var id: String { key }
}

struct Bill: Identifiable, Codable, Hashable {
    var id: String
    var cents: Int
    var type: BillType
    var note: String
    var iso: String
    var time: String
    var createdAt: Double
    var count: Int
    var kinds: Int
    var groups: [BillDenomGroup]

    private enum CodingKeys: String, CodingKey {
        case id, cents, type, note, iso, time, createdAt, count, kinds, groups
    }

    init(
        id: String,
        cents: Int,
        type: BillType,
        note: String,
        iso: String,
        time: String,
        createdAt: Double,
        count: Int,
        kinds: Int,
        groups: [BillDenomGroup]
    ) {
        self.id = id
        self.cents = cents
        self.type = type
        self.note = note
        self.iso = iso
        self.time = time
        self.createdAt = createdAt
        self.count = count
        self.kinds = kinds
        self.groups = groups
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        cents = try c.decodeIfPresent(Int.self, forKey: .cents) ?? 0
        type = try c.decodeIfPresent(BillType.self, forKey: .type) ?? .expense
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        iso = try c.decodeIfPresent(String.self, forKey: .iso) ?? DateHelp.todayISO
        time = try c.decodeIfPresent(String.self, forKey: .time) ?? ""
        createdAt = try c.decodeIfPresent(Double.self, forKey: .createdAt) ?? 0
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        kinds = try c.decodeIfPresent(Int.self, forKey: .kinds) ?? 0
        groups = try c.decodeIfPresent([BillDenomGroup].self, forKey: .groups) ?? []
    }

    var monthKey: String { String(iso.prefix(7)) }
    var signedAmountText: String {
        "\(type == .expense ? "−" : "+")¥\(Formats.money(cents))"
    }
    var typeLabel: String { type == .expense ? "支出" : "收入" }
    var fallbackTitle: String { type == .expense ? "现金支出" : "现金收入" }
    var title: String { note.isEmpty ? fallbackTitle : note }
}

struct BillsEnvelope: Codable {
    var v: Int
    var updatedAt: Double
    var bills: [Bill]

    init(v: Int = 1, updatedAt: Double = Date().timeIntervalSince1970 * 1000, bills: [Bill]) {
        self.v = v
        self.updatedAt = updatedAt
        self.bills = bills
    }
}

enum BillsCodec {
    private static let decoder = JSONDecoder()

    static func parse(_ raw: String) -> BillsEnvelope? {
        guard let data = raw.data(using: .utf8) else { return nil }
        if let envelope = try? decoder.decode(BillsEnvelope.self, from: data) {
            return envelope
        }
        if let bills = try? decoder.decode([Bill].self, from: data) {
            return BillsEnvelope(updatedAt: 0, bills: bills)
        }
        return nil
    }

    static func raw(_ bills: [Bill], updatedAt: Double = Date().timeIntervalSince1970 * 1000) -> String {
        let envelope = BillsEnvelope(updatedAt: updatedAt, bills: bills)
        guard let data = try? JSONEncoder().encode(envelope),
              let string = String(data: data, encoding: .utf8) else {
            return "{\"v\":1,\"updatedAt\":0,\"bills\":[]}"
        }
        return string
    }
}

struct Denomination: Identifiable, Hashable {
    let id: String
    let value: Int
    let name: String
    let imageName: String

    static let all: [Denomination] = [
        Denomination(id: "100", value: 10_000, name: "100元", imageName: "100"),
        Denomination(id: "50", value: 5_000, name: "50元", imageName: "50"),
        Denomination(id: "20", value: 2_000, name: "20元", imageName: "20"),
        Denomination(id: "10", value: 1_000, name: "10元", imageName: "10"),
        Denomination(id: "5", value: 500, name: "5元", imageName: "5"),
        Denomination(id: "1", value: 100, name: "1元", imageName: "1"),
        Denomination(id: "0.5", value: 50, name: "5角", imageName: "0.5"),
        Denomination(id: "0.2", value: 20, name: "2角", imageName: "0.2"),
        Denomination(id: "0.1", value: 10, name: "1角", imageName: "0.1"),
        Denomination(id: "0.05", value: 5, name: "5分", imageName: "0.05"),
        Denomination(id: "0.02", value: 2, name: "2分", imageName: "0.02"),
        Denomination(id: "0.01", value: 1, name: "1分", imageName: "0.01")
    ]

    static func find(_ key: String) -> Denomination? {
        all.first { $0.id == key }
    }
}

struct CashGroup: Identifiable, Hashable {
    let denomination: Denomination
    let count: Int
    var id: String { denomination.id }
}

enum CashBreakdown {
    static func groups(for cents: Int) -> [CashGroup] {
        guard cents > 0 else { return [] }
        var remainder = cents
        var result: [CashGroup] = []
        for denomination in Denomination.all {
            guard remainder >= denomination.value else { continue }
            let count = remainder / denomination.value
            if count > 0 {
                result.append(CashGroup(denomination: denomination, count: count))
                remainder -= count * denomination.value
            }
        }
        return remainder == 0 ? result : []
    }

    static func totalNotes(_ groups: [CashGroup]) -> Int {
        groups.reduce(0) { $0 + $1.count }
    }
}

enum DateHelp {
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "HH:mm"
        return f
    }()

    static var todayISO: String { isoFormatter.string(from: Date()) }

    static func date(from iso: String) -> Date? {
        isoFormatter.date(from: iso)
    }

    static func iso(from date: Date) -> String {
        isoFormatter.string(from: date)
    }

    static func time(from date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func monthStart(_ date: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    static func shiftMonth(_ date: Date, by value: Int) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .month, value: value, to: date) ?? date
    }

    static func monthKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    static func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }

    static func dayTitle(_ iso: String) -> String {
        guard let date = date(from: iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    static func fullDate(_ iso: String) -> String {
        guard let date = date(from: iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}

enum Formats {
    static func money(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: Double(abs(cents)) / 100.0)) ?? "0.00"
    }

    static func moneyValue(_ cents: Int) -> String {
        "¥\(money(cents))"
    }

    static func rawAmount(_ cents: Int) -> String {
        let yuan = Double(cents) / 100
        if yuan.rounded() == yuan {
            return String(Int(yuan))
        }
        return String(format: "%.2f", yuan)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }

    static func inputCents(_ raw: String) -> Int {
        guard !raw.isEmpty, raw != "." else { return 0 }
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        let whole = Int(String(parts.first ?? "0")) ?? 0
        var fraction = 0
        if parts.count > 1 {
            let digits = String(parts[1].prefix(2))
            fraction = Int(digits.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        }
        return whole * 100 + fraction
    }

    static func amountInput(_ cents: Int, trailingDecimal: Bool = false) -> String {
        let whole = cents / 100
        let fraction = cents % 100
        if trailingDecimal { return "\(whole)." }
        if fraction == 0 { return "\(whole)" }
        return String(format: "%d.%02d", whole, fraction)
    }
}
