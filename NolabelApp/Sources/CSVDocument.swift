import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var data = Data()
        data.append(contentsOf: [0xEF, 0xBB, 0xBF])
        data.append(text.data(using: .utf8) ?? Data())
        return FileWrapper(regularFileWithContents: data)
    }
}

enum CSVError: LocalizedError {
    case empty
    case missingColumns([String])
    case badRow(Int, String)

    var errorDescription: String? {
        switch self {
        case .empty:
            "CSV 里没有账单"
        case .missingColumns(let names):
            "CSV 缺少列：\(names.joined(separator: "、"))"
        case .badRow(let line, let message):
            "第 \(line) 行：\(message)"
        }
    }
}

enum CSVCodec {
    static func rows(from text: String) -> [[String]] {
        let source = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = source.startIndex

        while index < source.endIndex {
            let character = source[index]
            if quoted {
                if character == "\"" {
                    let next = source.index(after: index)
                    if next < source.endIndex, source[next] == "\"" {
                        field.append("\"")
                        index = source.index(after: next)
                        continue
                    }
                    quoted = false
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    quoted = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                default:
                    field.append(character)
                }
            }
            index = source.index(after: index)
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    static func parse(_ text: String) throws -> [Bill] {
        let rows = rows(from: text).filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        guard rows.count >= 2 else { throw CSVError.empty }
        let header = rows[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        func index(_ names: [String]) -> Int? {
            header.firstIndex { names.contains($0) }
        }
        let idIndex = index(["编号", "id"])
        let dateIndex = index(["日期", "date"])
        let timeIndex = index(["时间", "time"])
        let typeIndex = index(["类型", "type"])
        let amountIndex = index(["金额", "amount"])
        let noteIndex = index(["备注", "note"])

        var missing: [String] = []
        if dateIndex == nil { missing.append("日期") }
        if timeIndex == nil { missing.append("时间") }
        if typeIndex == nil { missing.append("类型") }
        if amountIndex == nil { missing.append("金额") }
        if !missing.isEmpty { throw CSVError.missingColumns(missing) }

        var bills: [Bill] = []
        var seen = Set<String>()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2
            func field(_ index: Int?) -> String {
                guard let index, row.indices.contains(index) else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let dateText = field(dateIndex)
            let timeText = field(timeIndex)
            let typeText = field(typeIndex)
            let amountText = field(amountIndex).replacingOccurrences(of: "¥", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard formatter.date(from: dateText) != nil else {
                throw CSVError.badRow(line, "日期格式应为 YYYY-MM-DD")
            }
            let timeParts = timeText.split(separator: ":")
            guard timeParts.count == 2,
                  let hour = Int(timeParts[0]), let minute = Int(timeParts[1]),
                  (0...23).contains(hour), (0...59).contains(minute) else {
                throw CSVError.badRow(line, "时间格式应为 HH:mm")
            }
            let type: BillType
            switch typeText {
            case "支出", "expense", "exp": type = .expense
            case "收入", "income", "inc": type = .income
            default: throw CSVError.badRow(line, "类型应为支出或收入")
            }
            guard let decimal = Decimal(string: amountText), decimal > 0 else {
                throw CSVError.badRow(line, "金额必须大于 0")
            }
            let cents = Int((decimal * Decimal(100)).rounded())
            guard cents >= 1 else { throw CSVError.badRow(line, "金额最小到 0.01 元") }
            let groups = CashBreakdown.groups(for: cents)
            guard !groups.isEmpty else { throw CSVError.badRow(line, "金额无法组合成现钞") }
            let id = field(idIndex).isEmpty
                ? "\(Int(Date().timeIntervalSince1970 * 1000))\(UUID().uuidString.prefix(4))"
                : field(idIndex)
            guard !seen.contains(id) else { throw CSVError.badRow(line, "编号重复") }
            seen.insert(id)
            let createdAt = Date().timeIntervalSince1970 * 1000 + Double(offset)
            bills.append(
                Bill(
                    id: id,
                    cents: cents,
                    type: type,
                    note: field(noteIndex),
                    iso: dateText,
                    time: timeText,
                    createdAt: createdAt,
                    count: CashBreakdown.totalNotes(groups),
                    kinds: groups.count,
                    groups: groups.map { BillDenomGroup(key: $0.denomination.id, count: $0.count) }
                )
            )
        }
        guard !bills.isEmpty else { throw CSVError.empty }
        return bills
    }

    static func csv(for bills: [Bill]) -> String {
        var lines = ["编号,日期,时间,类型,金额,备注"]
        let sorted = bills.sorted {
            if $0.iso != $1.iso { return $0.iso > $1.iso }
            return $0.createdAt > $1.createdAt
        }
        for bill in sorted {
            let amount = String(format: "%.2f", Double(bill.cents) / 100)
            lines.append([
                escape(bill.id),
                escape(bill.iso),
                escape(bill.time),
                bill.type == .expense ? "支出" : "收入",
                amount,
                escape(bill.note)
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
