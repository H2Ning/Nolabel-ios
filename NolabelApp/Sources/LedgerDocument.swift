import Foundation

struct LedgerDocument: Codable {
    static let formatName = "nolabel.ledger"
    static let currentSchemaVersion = 1

    var format: String
    var schemaVersion: Int
    var ledgerID: String
    var updatedAt: Double
    var exportedAt: Double
    var bills: [Bill]
    var settings: LedgerSettings?

    init(
        ledgerID: String,
        updatedAt: Double,
        exportedAt: Double,
        bills: [Bill],
        settings: LedgerSettings? = nil
    ) {
        self.format = Self.formatName
        self.schemaVersion = Self.currentSchemaVersion
        self.ledgerID = ledgerID
        self.updatedAt = updatedAt
        self.exportedAt = exportedAt
        self.bills = bills
        self.settings = settings
    }
}

struct LedgerSettings: Codable {
    var theme: String?
    var haptic: String?
    var numberFormat: NumberFormatSettings?
    var sortDesc: Bool?
    var deleteConfirm: Bool?
    var cashMode: Int?
    var plazaStageMode: Int?
}

enum LedgerCodec {
    private static let decoder = JSONDecoder()

    static func parse(_ raw: String) -> LedgerDocument? {
        guard let data = raw.data(using: .utf8),
              let document = try? decoder.decode(LedgerDocument.self, from: data) else {
            return nil
        }
        guard document.format == LedgerDocument.formatName,
              document.schemaVersion == LedgerDocument.currentSchemaVersion,
              !document.ledgerID.isEmpty else {
            return nil
        }
        return document
    }

    static func raw(_ document: LedgerDocument) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(document) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
