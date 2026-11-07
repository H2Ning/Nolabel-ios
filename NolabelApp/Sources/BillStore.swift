import Foundation

final class BillStore {
    static let shared = BillStore()

    private let fileManager = FileManager.default
    private let directory: URL
    private let fileURL: URL
    private let backupURL: URL
    private let snapshotsDirectory: URL
    private let exportURL: URL
    private let snapshotsLimit = 30
    private let snapshotFormatter: DateFormatter

    private init() {
        let base = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        directory = base.appendingPathComponent("Nolabel", isDirectory: true)
        fileURL = directory.appendingPathComponent("ledger.json")
        backupURL = directory.appendingPathComponent("ledger.backup.json")
        snapshotsDirectory = directory.appendingPathComponent("Snapshots", isDirectory: true)
        exportURL = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Nolabel-backup.json")

        snapshotFormatter = DateFormatter()
        snapshotFormatter.locale = Locale(identifier: "en_US_POSIX")
        snapshotFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        snapshotFormatter.dateFormat = "yyyyMMdd-HHmmss"

        createDirectoryIfNeeded()
        createSnapshotsDirectoryIfNeeded()
    }

    func loadDocument() -> LedgerDocument? {
        if let document = document(at: fileURL) {
            return document
        }
        if let document = document(at: backupURL) {
            restore(from: backupURL)
            return document
        }
        if let snapshot = latestSnapshot() {
            restore(from: snapshot.url)
            return snapshot.document
        }
        if let document = document(at: exportURL) {
            restore(from: exportURL)
            return document
        }
        return nil
    }

    @discardableResult
    func saveDocument(_ document: LedgerDocument) -> Bool {
        guard let raw = LedgerCodec.raw(document) else { return false }
        return saveRaw(raw)
    }

    private func saveRaw(_ raw: String) -> Bool {
        guard LedgerCodec.parse(raw) != nil,
              let data = raw.data(using: .utf8) else {
            return false
        }

        if let current = rawString(at: fileURL), current == raw {
            writeExport(data, raw: raw)
            return true
        }

        createDirectoryIfNeeded()
        createSnapshotsDirectoryIfNeeded()

        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.copyItem(at: fileURL, to: backupURL)
            applyProtection(to: backupURL)
        }

        do {
            try data.write(to: fileURL, options: [.atomic])
            applyProtection(to: fileURL)
            writeSnapshot(data)
            writeExport(data, raw: raw)
            return true
        } catch {
            return false
        }
    }

    private func writeExport(_ data: Data, raw: String) {
        if let current = rawString(at: exportURL), current == raw {
            return
        }
        try? data.write(to: exportURL, options: [.atomic])
        applyProtection(to: exportURL)
    }

    private func writeSnapshot(_ data: Data) {
        let name = "ledger-\(snapshotFormatter.string(from: Date())).json"
        let url = snapshotsDirectory.appendingPathComponent(name)
        try? data.write(to: url, options: [.atomic])
        applyProtection(to: url)
        pruneSnapshots()
    }

    private func pruneSnapshots() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: snapshotsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        let snapshots = files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        guard snapshots.count > snapshotsLimit else {
            return
        }
        for url in snapshots.dropFirst(snapshotsLimit) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func latestSnapshot() -> (document: LedgerDocument, url: URL)? {
        guard let files = try? fileManager.contentsOfDirectory(
            at: snapshotsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        let snapshots = files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for url in snapshots {
            if let document = document(at: url) {
                return (document, url)
            }
        }
        return nil
    }

    private func restore(from url: URL) {
        try? fileManager.removeItem(at: fileURL)
        try? fileManager.copyItem(at: url, to: fileURL)
        applyProtection(to: fileURL)
    }

    private func createDirectoryIfNeeded() {
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
    }

    private func createSnapshotsDirectoryIfNeeded() {
        try? fileManager.createDirectory(
            at: snapshotsDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
    }

    private func applyProtection(to url: URL) {
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    private func document(at url: URL) -> LedgerDocument? {
        guard let raw = rawString(at: url) else { return nil }
        return LedgerCodec.parse(raw)
    }

    private func rawString(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        return raw
    }
}
