import Foundation
import WidgetKit

/// The one value the home-screen widget needs from the app. The app writes it
/// into the shared App Group whenever the ledger changes; the widget never
/// touches the network or the app's local store.
struct VerdictSnapshot: Codable, Equatable {
    var monthISO: String
    var monthLabel: String
    var verdictTitle: String
    var metricLabel: String
    var amountText: String
    var countLabel: String

    static let appGroup = "group.com.h2ning.nolabel"
    static let storageKey = "nolabel.verdict.snapshot.v1"
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
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(VerdictSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: Self.appGroup),
              let data = try? JSONEncoder().encode(self)
        else { return }
        defaults.set(data, forKey: Self.storageKey)
        WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
    }
}
