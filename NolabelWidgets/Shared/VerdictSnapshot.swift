import Foundation
import WidgetKit

/// The one value the home-screen widget needs from the app. The app writes it
/// into the shared App Group container whenever the ledger changes; the widget
/// never touches the network or the app's local store.
struct VerdictSnapshot: Codable, Equatable {
    var monthISO: String
    var monthLabel: String
    var verdictTitle: String
    var metricLabel: String
    var amountText: String
    var countLabel: String

    static let appGroup = "group.com.h2ning.nolabel"
    static let fileName = "verdict-snapshot.json"
    static let widgetKind = "NolabelVerdictWidget"
    static let deepLink = URL(string: "nolabel://verdict")!

    static let placeholder = VerdictSnapshot(
        monthISO: "",
        monthLabel: "本月",
        verdictTitle: "收支相抵，两袖清风",
        metricLabel: "支出",
        amountText: "¥0.00",
        countLabel: "共 0 笔"
    )

    /// Nil when the signature does not include the App Group. Both processes
    /// check this before reading or writing, and the widget can say so.
    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static var isSharedContainerAvailable: Bool {
        sharedContainerURL != nil
    }

    private static var fileURL: URL? {
        sharedContainerURL?.appendingPathComponent(fileName)
    }

    static func currentMonthISO(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    static func currentMonthLabel(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月"
        return formatter.string(from: date)
    }

    static func load() -> VerdictSnapshot? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(VerdictSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }

    func save() {
        guard let url = Self.fileURL,
              let data = try? JSONEncoder().encode(self)
        else { return }
        try? data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
