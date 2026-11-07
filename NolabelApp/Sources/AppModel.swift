import Foundation
import Observation
import SwiftUI
import UIKit

enum PlazaDetent: String, Hashable {
    case small, medium, large
}

enum SettingsSubview: Hashable {
    case main
    case personalization
    case appearance
    case icon
    case numberFormat
    case haptics
    case dataSecurity
}

enum EntryOperator: String, CaseIterable {
    case add = "+"
    case subtract = "−"
    case multiply = "×"
    case divide = "÷"

    var next: EntryOperator {
        switch self {
        case .add: .subtract
        case .subtract: .multiply
        case .multiply: .divide
        case .divide: .add
        }
    }

    var label: String {
        switch self {
        case .add: "加"
        case .subtract: "减"
        case .multiply: "乘"
        case .divide: "除"
        }
    }
}

@Observable
@MainActor
final class AppModel {
    private let defaults = UserDefaults.standard
    private let plazaSmallHeightKey = "nolabel-plaza-small-height"
    private let plazaMediumHeightKey = "nolabel-plaza-medium-height"

    /// The last measured content heights. They are used as the sheet's detents
    /// on the next presentation, so the sheet never resizes while it opens.
    var plazaSmallHeight: CGFloat? {
        get {
            let value = defaults.double(forKey: plazaSmallHeightKey)
            return value > 0 ? CGFloat(value) : nil
        }
        set {
            guard let newValue else { return }
            defaults.set(Double(newValue), forKey: plazaSmallHeightKey)
        }
    }

    var plazaMediumHeight: CGFloat? {
        get {
            let value = defaults.double(forKey: plazaMediumHeightKey)
            return value > 0 ? CGFloat(value) : nil
        }
        set {
            guard let newValue else { return }
            defaults.set(Double(newValue), forKey: plazaMediumHeightKey)
        }
    }
    private let deviceIDKey = "nolabel-device-id"
    private let themeKey = "nolabel-theme"
    private let sortKey = "nolabel-sort-desc"
    private let cashModeKey = "nolabel-cash-mode"
    private let plazaStageModeKey = "nolabel-plaza-stage-mode"
    private let hapticKey = "nolabel-haptic-level"
    private let numberFormatKey = "nolabel-number-format"
    private let deleteConfirmKey = "nolabel-delete-confirm"
    private let showBillTimeKey = "nolabel-show-bill-time"
    private let monthKey = "nolabel-selected-month"
    private let plazaDetentKey = "nolabel-plaza-detent"
    private let draftInputKey = "nolabel-entry-draft-input"
    private let draftNoteKey = "nolabel-entry-draft-note"
    private let draftTypeKey = "nolabel-entry-draft-type"
    private let draftAtKey = "nolabel-entry-draft-at"

    let previewMode: Bool
    var pendingDeleteBill: Bill?
    var deleteConfirmEnabled: Bool {
        didSet { defaults.set(deleteConfirmEnabled, forKey: deleteConfirmKey) }
    }
    private(set) var undoDeleteTitle: String?
    private var deleteUndoSnapshot: [Bill]?
    private var undoTask: Task<Void, Never>?
    var cashPlazaOpen = false
    private(set) var ledgerID: String = UUID().uuidString.lowercased()
    private(set) var deviceID: String = ""

    var bills: [Bill] = [] {
        didSet { billsRevision &+= 1 }
    }
    var dataMessage = ""
    var dataMessageIsError = false

    var themeMode: ThemeMode
    var hapticLevel: HapticLevel
    var appIcon: AppIconChoice
    var numberFormat: NumberFormatSettings
    var sortDesc: Bool
    var showBillTime: Bool {
        didSet { defaults.set(showBillTime, forKey: showBillTimeKey) }
    }
    var selectedMonth: Date {
        didSet { defaults.set(selectedMonth, forKey: monthKey) }
    }
    var plazaDetent: PlazaDetent {
        didSet { defaults.set(plazaDetent.rawValue, forKey: plazaDetentKey) }
    }
    var settingsPath: [SettingsSubview] = []

    var settingsOpen: Bool {
        get { !settingsPath.isEmpty }
        set {
            if newValue {
                if settingsPath.isEmpty { settingsPath = [.main] }
            } else {
                settingsPath = []
            }
        }
    }

    var settingsSubview: SettingsSubview {
        get { settingsPath.last ?? .main }
        set {
            guard !settingsPath.isEmpty else { return }
            if newValue == .main {
                settingsPath = [.main]
            } else {
                settingsPath.removeAll { $0 != .main }
                settingsPath.append(newValue)
            }
        }
    }
    /// Pushes one settings page while keeping the stack, so Back always
    /// returns to the previous page instead of the settings root.
    func pushSettings(_ sub: SettingsSubview) {
        guard !settingsPath.isEmpty else { return }
        if sub == .main {
            settingsPath = [.main]
        } else if settingsPath.last != sub {
            settingsPath.append(sub)
        }
    }

    var openBillID: String?
    var lastSavedBillID: String?
    var writing = false

    var entryOpen = false
    var entryEditingID: String?
    var entryInput = "" {
        didSet { persistEntryDraft() }
    }
    var entryTrailingDecimal = false
    var entryJustEvaluated = false
    var entryType: BillType = .expense {
        didSet { persistEntryDraft() }
    }
    var entryNote = "" {
        didSet { persistEntryDraft() }
    }
    var entryDate = Date()
    var entryAccumulator: Int?
    var entryOperator: EntryOperator?
    var entryWaitingForOperand = false
    var dateSheetOpen = false
    var entryError = ""
    var cashMode = 1
    var plazaStageMode: Int {
        didSet { defaults.set(plazaStageMode, forKey: plazaStageModeKey) }
    }

    private var entryOperatorTapIndex = 0
    private var entryOperatorTapAt: TimeInterval = 0
    var palette: AppPalette {
        AppPalette
            .palette(themeMode == .system ? currentSystemScheme : (themeMode == .dark ? .dark : .light))
            .withNumberColors(numberFormat.colorScheme)
    }

    private var currentSystemScheme: ColorScheme {
        UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
    }

    var preferredColorScheme: ColorScheme? {
        themeMode.colorScheme
    }

    var selectedMonthKey: String { DateHelp.monthKey(selectedMonth) }

    /// A cheap value that changes whenever the selected month's visible data
    /// changes. Views use it to invalidate their own derived values.
    var monthDataVersion: String {
        "\(billsRevision)|\(selectedMonthKey)|\(sortDesc)"
    }

    private struct MonthSnapshot {
        let bills: [Bill]
        let expense: Int
        let income: Int
        let notes: Int
        let groups: [DayGroup]
    }

    private var billsRevision = 0
    private var billsByMonth: [String: [Bill]] = [:]
    private var billsByMonthRevision = -1
    private var cachedMonthSnapshot: MonthSnapshot?
    private var cachedMonthSnapshotKey = ""

    private func billsForSelectedMonth() -> [Bill] {
        if billsByMonthRevision != billsRevision {
            var map: [String: [Bill]] = [:]
            for bill in bills {
                map[bill.monthKey, default: []].append(bill)
            }
            billsByMonth = map
            billsByMonthRevision = billsRevision
        }
        return billsByMonth[selectedMonthKey] ?? []
    }

    private func monthSnapshot() -> MonthSnapshot {
        let key = monthDataVersion
        if key == cachedMonthSnapshotKey, let cached = cachedMonthSnapshot {
            return cached
        }

        let sorted = billsForSelectedMonth()
            .sorted { lhs, rhs in
                if lhs.iso != rhs.iso { return sortDesc ? lhs.iso > rhs.iso : lhs.iso < rhs.iso }
                if lhs.createdAt != rhs.createdAt { return sortDesc ? lhs.createdAt > rhs.createdAt : lhs.createdAt < rhs.createdAt }
                return lhs.id > rhs.id
            }

        var expense = 0
        var income = 0
        var notes = 0
        var order: [String] = []
        var grouped: [String: [Bill]] = [:]
        for bill in sorted {
            if bill.type == .expense { expense += bill.cents } else { income += bill.cents }
            notes += bill.count
            if grouped[bill.iso] == nil {
                order.append(bill.iso)
                grouped[bill.iso] = []
            }
            grouped[bill.iso]?.append(bill)
        }

        let groups = order.map { iso -> DayGroup in
            let items = grouped[iso] ?? []
            var dayExpense = 0
            var dayIncome = 0
            for bill in items {
                if bill.type == .expense { dayExpense += bill.cents } else { dayIncome += bill.cents }
            }
            return DayGroup(iso: iso, bills: items, expense: dayExpense, income: dayIncome)
        }

        let snapshot = MonthSnapshot(
            bills: sorted,
            expense: expense,
            income: income,
            notes: notes,
            groups: groups
        )
        cachedMonthSnapshot = snapshot
        cachedMonthSnapshotKey = key
        return snapshot
    }

    var monthBills: [Bill] { monthSnapshot().bills }
    var monthExpense: Int { monthSnapshot().expense }
    var monthIncome: Int { monthSnapshot().income }
    var monthNotes: Int { monthSnapshot().notes }
    func monthGroups() -> [DayGroup] { monthSnapshot().groups }

    var monthTitle: String { DateHelp.monthTitle(selectedMonth) }
    var monthPeriod: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月"
        return formatter.string(from: selectedMonth)
    }

    var entryCents: Int {
        Formats.inputCents(entryInput)
    }

    var entryDisplay: String {
        if let left = entryAccumulator, let op = entryOperator {
            let right = entryWaitingForOperand ? "" : Formats.formattedInput(entryInput)
            return "\(Formats.compactMoney(left))\(op.rawValue)\(right)"
        }
        guard !entryInput.isEmpty else { return "0.00" }
        return Formats.formattedInput(entryInput)
    }

    var entryPreviewCents: Int {
        guard let left = entryAccumulator, let op = entryOperator else { return entryCents }
        if entryWaitingForOperand { return left }
        guard let result = Self.operationResult(left, op, entryCents) else { return 0 }
        return max(0, result)
    }

    var entryGroups: [CashGroup] {
        CashBreakdown.groups(for: entryPreviewCents)
    }

    var entryNotePlaceholder: String {
        "备注"
    }

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        previewMode = arguments.contains("--preview")
        let storedTheme = defaults.string(forKey: themeKey) ?? ThemeMode.system.rawValue
        themeMode = ThemeMode(rawValue: storedTheme) ?? .system
        hapticLevel = HapticLevel(rawValue: defaults.string(forKey: hapticKey) ?? "") ?? .rich
        appIcon = AppIconChoice.current
        if let data = defaults.data(forKey: numberFormatKey),
           let stored = try? JSONDecoder().decode(NumberFormatSettings.self, from: data) {
            numberFormat = stored
        } else {
            numberFormat = NumberFormatSettings()
        }
        sortDesc = defaults.object(forKey: sortKey) as? Bool ?? true
        showBillTime = defaults.object(forKey: showBillTimeKey) as? Bool ?? true
        deleteConfirmEnabled = defaults.object(forKey: deleteConfirmKey) as? Bool ?? true
        let storedCashMode = defaults.integer(forKey: cashModeKey)
        cashMode = (1...3).contains(storedCashMode) ? storedCashMode : 1
        let storedPlazaMode = defaults.integer(forKey: plazaStageModeKey)
        plazaStageMode = (1...3).contains(storedPlazaMode) ? storedPlazaMode : 2
        if ProcessInfo.processInfo.arguments.contains("--preview-plaza-analysis") {
            plazaDetent = .large
        } else if let raw = defaults.string(forKey: plazaDetentKey),
                  let stored = PlazaDetent(rawValue: raw) {
            plazaDetent = stored
        } else {
            plazaDetent = .medium
        }
        if let storedMonth = defaults.object(forKey: monthKey) as? Date {
            selectedMonth = DateHelp.monthStart(storedMonth)
        } else {
            selectedMonth = DateHelp.monthStart(Date())
        }

        if let document = BillStore.shared.loadDocument() {
            bills = document.bills
            ledgerID = document.ledgerID
        }
        let storedDeviceID = defaults.string(forKey: deviceIDKey)
        deviceID = storedDeviceID ?? UUID().uuidString.lowercased()
        if storedDeviceID == nil {
            defaults.set(deviceID, forKey: deviceIDKey)
        }

        if previewMode {
            configurePreview(arguments: arguments)
        }
        Formats.apply(numberFormat)
        Haptics.setLevel(hapticLevel)
        if !AppIconChoice.isCurrentIconAllowed {
            Task { @MainActor in
                try? await UIApplication.shared.setAlternateIconName(nil)
            }
        }
    }

    private func configurePreview(arguments: [String]) {
        themeMode = value(after: "--preview-theme", in: arguments).flatMap(ThemeMode.init(rawValue:)) ?? .dark
        bills = SampleData.bills

        let screen = value(after: "--preview-screen", in: arguments)
        if screen == "settings" {
            settingsOpen = true
            switch value(after: "--preview-settings", in: arguments) {
            case "appearance": settingsSubview = .appearance
            case "number-format": settingsSubview = .numberFormat
            case "haptics": settingsSubview = .haptics
            default: break
            }
        } else if screen == "entry" {
            entryOpen = true
            if let raw = value(after: "--preview-amount", in: arguments) {
                entryInput = raw
            } else {
                entryInput = "52145"
            }
            if let raw = value(after: "--preview-cash-mode", in: arguments),
               let value = Int(raw),
               (1...3).contains(value) {
                cashMode = value
            }
            entryType = .expense
            entryNote = ""
        } else {
            if arguments.contains("--preview-open"), let first = SampleData.bills.first {
                openBillID = first.id
            }
        }

        if arguments.contains("--preview-calc") {
            entryOpen = true
            entryInput = "5"
            selectOperator(.multiply)
            pressDigit("3")
            pressEquals()
        }
        if arguments.contains("--preview-expression") {
            entryOpen = true
            entryInput = "1"
            selectOperator(.add)
            pressDigit("2")
        }
        if arguments.contains("--preview-negative") {
            entryOpen = true
            entryInput = "1"
            selectOperator(.subtract)
            pressDigit("2")
            pressEquals()
        }
        if arguments.contains("--preview-backspace") {
            entryOpen = true
            entryInput = "1"
            selectOperator(.add)
            pressDigit("2")
            pressBackspace()
        }
        if arguments.contains("--preview-backspace-twice") {
            entryOpen = true
            entryInput = "1"
            selectOperator(.add)
            pressDigit("2")
            pressBackspace()
            pressBackspace()
        }
        if arguments.contains("--preview-delete-confirm"), let first = bills.first {
            pendingDeleteBill = first
        }
        if arguments.contains("--preview-plaza") {
            cashPlazaOpen = true
        }
        if arguments.contains("--preview-number-alt") {
            numberFormat.incomeFormat = .plus
            numberFormat.expenseFormat = .bracket
            numberFormat.separator = .tenThousand
            numberFormat.colorScheme = .redCyan
        }
        if arguments.contains("--preview-autoplay-month") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                guard let self else { return }
                withAnimation(AppMotion.spring) { self.shiftMonth(-1) }
            }
        }
        if arguments.contains("--preview-autoplay-entry") {
            for index in 0..<5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 + Double(index) * 0.8) { [weak self] in
                    guard let self else { return }
                    withAnimation(AppMotion.drawer) {
                        if self.entryOpen {
                            self.closeEntry()
                        } else {
                            self.openEntry(self.bills.first)
                        }
                    }
                }
            }
        }
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private func persistLedger(bills: [Bill]) -> Bool {
        let now = Date().timeIntervalSince1970 * 1000
        let document = LedgerDocument(
            ledgerID: ledgerID,
            updatedAt: now,
            exportedAt: now,
            bills: bills
        )
        return BillStore.shared.saveDocument(document)
    }

    func saveBills(_ next: [Bill]) async -> Bool {
        writing = true
        defer { writing = false }
        guard persistLedger(bills: next) else {
            dataMessage = "保存失败，请检查存储空间后重试"
            dataMessageIsError = true
            Haptics.error()
            return false
        }
        bills = next
        dataMessage = ""
        dataMessageIsError = false
        return true
    }

    func requestDelete(_ bill: Bill) {
        if deleteConfirmEnabled {
            pendingDeleteBill = bill
            Haptics.deletePrompt()
        } else {
            Task { await delete(bill) }
        }
    }

    func cancelDeletePrompt() {
        pendingDeleteBill = nil
        Haptics.soft()
    }

    func confirmDeletePrompt() {
        guard let bill = pendingDeleteBill else { return }
        pendingDeleteBill = nil
        // Let the alert finish dismissing before the list mutates.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            await delete(bill)
        }
    }

    func delete(_ bill: Bill) async {
        let snapshot = bills
        let next = bills.filter { $0.id != bill.id }
        if await saveBills(next) {
            Haptics.deleteCommitted()
            openBillID = nil
            deleteUndoSnapshot = snapshot
            undoDeleteTitle = bill.title
            undoTask?.cancel()
            undoTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                self?.clearUndo()
            }
        }
    }

    func undoDelete() async {
        guard let snapshot = deleteUndoSnapshot else { return }
        undoTask?.cancel()
        clearUndo()
        if await saveBills(snapshot) {
            Haptics.success()
        }
    }

    private func clearUndo() {
        undoDeleteTitle = nil
        deleteUndoSnapshot = nil
    }

    func shiftMonth(_ value: Int) {
        let previousYear = Calendar.current.component(.year, from: selectedMonth)
        selectedMonth = DateHelp.shiftMonth(selectedMonth, by: value)
        let nextYear = Calendar.current.component(.year, from: selectedMonth)
        Haptics.monthShift(crossesYear: previousYear != nextYear)
    }

    func cycleCashMode() {
        setCashMode(cashMode % 3 + 1)
    }

    func setCashMode(_ value: Int) {
        guard (1...3).contains(value) else { return }
        cashMode = value
        defaults.set(cashMode, forKey: cashModeKey)
        Haptics.cashMode(cashMode)
    }

    var csvExportText: String {
        CSVCodec.csv(for: bills)
    }

    /// Deletes every bill from the local ledger. The caller must confirm first.
    @discardableResult
    func clearAllBills() async -> Bool {
        guard !bills.isEmpty else { return true }
        if await saveBills([]) {
            selectedMonth = DateHelp.monthStart(Date())
            openBillID = nil
            pendingDeleteBill = nil
            clearUndo()
            Haptics.success()
            return true
        }
        return false
    }

    @discardableResult
    func importCSV(_ text: String) async -> Bool {
        do {
            let imported = try CSVCodec.parse(text)
            var map: [String: Bill] = [:]
            for bill in bills { map[bill.id] = bill }
            for bill in imported { map[bill.id] = bill }
            let next = map.values.sorted { $0.createdAt > $1.createdAt }
            if await saveBills(next) {
                if let latest = next.max(by: { $0.iso < $1.iso }), let date = DateHelp.date(from: latest.iso) {
                    selectedMonth = DateHelp.monthStart(date)
                }
                dataMessage = ""
                dataMessageIsError = false
                Haptics.success()
                return true
            }
            return false
        } catch {
            dataMessage = (error as? LocalizedError)?.errorDescription ?? "CSV 读取失败"
            dataMessageIsError = true
            settingsOpen = true
            Haptics.warning()
            return false
        }
    }

    /// Switches the home-screen icon. The primary icon is set with `nil`,
    /// every other choice uses its asset-catalog name.
    func setAppIcon(_ choice: AppIconChoice) async -> Bool {
        guard UIApplication.shared.supportsAlternateIcons else { return false }
        if choice != appIcon {
            do {
                AlternateIconAlert.suppress()
                try await UIApplication.shared.setAlternateIconName(
                    choice.isPrimary ? nil : choice.assetName
                )
                appIcon = choice
            } catch {
                return false
            }
        }
        return true
    }

    func setHapticLevel(_ value: HapticLevel) {
        let changed = value != hapticLevel
        if changed {
            hapticLevel = value
            defaults.set(value.rawValue, forKey: hapticKey)
            Haptics.setLevel(value)
        }
        if value == .rich {
            // Tapping 丰富 always auditions the double-tap confirmation.
            Haptics.doubleTapConfirm()
        } else if changed {
            Haptics.pick()
        }
    }

    func updateNumberFormat(_ change: (inout NumberFormatSettings) -> Void) {
        var next = numberFormat
        change(&next)
        guard next != numberFormat else { return }
        numberFormat = next
        Formats.apply(next)
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: numberFormatKey)
        }
        Haptics.pick()
    }

    func setTheme(_ mode: ThemeMode) {
        guard mode != themeMode else { return }
        withAnimation(AppMotion.grace) {
            themeMode = mode
        }
        defaults.set(mode.rawValue, forKey: themeKey)
        Haptics.pick()
    }

    func setSort(descending: Bool) {
        sortDesc = descending
        defaults.set(descending, forKey: sortKey)
    }

    func toggleSort() {
        setSort(descending: !sortDesc)
        Haptics.pick()
    }

    func openSettings() {
        settingsSubview = .main
        settingsOpen = true
        Haptics.soft()
    }

    func closeSettings() {
        settingsOpen = false
        settingsSubview = .main
        Haptics.soft()
    }

    func openEntry(_ bill: Bill? = nil) {
        dateSheetOpen = false
        entryEditingID = bill?.id
        if let bill {
            entryInput = Formats.amountInput(bill.cents)
            entryTrailingDecimal = false
            entryType = bill.type
            entryNote = bill.note
            entryDate = DateHelp.date(from: bill.iso) ?? Date()
            let components = bill.time.split(separator: ":").compactMap { Int($0) }
            if components.count == 2 {
                entryDate = Calendar.current.date(bySettingHour: components[0], minute: components[1], second: 0, of: entryDate) ?? entryDate
            }
        } else {
            entryInput = ""
            entryTrailingDecimal = false
            entryType = .expense
            entryNote = ""
            entryDate = Date()
            restoreEntryDraft()
        }
        entryAccumulator = nil
        entryOperator = nil
        entryWaitingForOperand = false
        entryJustEvaluated = false
        entryError = ""
        resetOperatorCycle()
        entryOpen = true
        Haptics.soft()
    }

    func closeEntry() {
        guard entryOpen else { return }
        let wasEditing = entryEditingID != nil
        entryOpen = false
        entryEditingID = nil
        entryInput = ""
        entryNote = ""
        entryError = ""
        entryOperator = nil
        entryAccumulator = nil
        entryWaitingForOperand = false
        resetOperatorCycle()
        dateSheetOpen = false
        if !wasEditing {
            clearEntryDraft()
        }
        Haptics.soft()
    }

    private func persistEntryDraft() {
        guard entryOpen, entryEditingID == nil else { return }
        defaults.set(entryInput, forKey: draftInputKey)
        defaults.set(entryNote, forKey: draftNoteKey)
        defaults.set(entryType.rawValue, forKey: draftTypeKey)
        defaults.set(Date(), forKey: draftAtKey)
    }

    private func restoreEntryDraft() {
        guard let savedAt = defaults.object(forKey: draftAtKey) as? Date,
              Date().timeIntervalSince(savedAt) < 24 * 60 * 60 else {
            clearEntryDraft()
            return
        }
        let input = defaults.string(forKey: draftInputKey) ?? ""
        let note = defaults.string(forKey: draftNoteKey) ?? ""
        guard !input.isEmpty || !note.isEmpty else { return }
        entryInput = input
        entryNote = note
        entryType = BillType(rawValue: defaults.string(forKey: draftTypeKey) ?? "") ?? .expense
    }

    private func clearEntryDraft() {
        defaults.removeObject(forKey: draftInputKey)
        defaults.removeObject(forKey: draftNoteKey)
        defaults.removeObject(forKey: draftTypeKey)
        defaults.removeObject(forKey: draftAtKey)
    }

    func saveEntry() async {
        guard let cents = finalizeEntryCents() else { return }
        guard cents > 0 else {
            entryError = "金额必须大于 0"
            Haptics.warning()
            return
        }
        let groups = CashBreakdown.groups(for: cents)
        guard !groups.isEmpty else {
            entryError = "这个金额暂时无法组合"
            Haptics.warning()
            return
        }
        let now = Date().timeIntervalSince1970 * 1000
        let wasEditing = entryEditingID != nil
        let iso = DateHelp.iso(from: entryDate)
        let time = DateHelp.time(from: entryDate)
        let fields = (
            cents: cents,
            type: entryType,
            note: entryNote.trimmingCharacters(in: .whitespacesAndNewlines),
            iso: iso,
            time: time,
            count: CashBreakdown.totalNotes(groups),
            kinds: groups.count,
            groups: groups.map { BillDenomGroup(key: $0.denomination.id, count: $0.count) }
        )

        var next = bills
        let bill: Bill
        if let editing = entryEditingID,
           let index = next.firstIndex(where: { $0.id == editing }) {
            let previous = next[index]
            let timestamp = previous.createdAt
            bill = Bill(
                id: previous.id,
                cents: fields.cents,
                type: fields.type,
                note: fields.note,
                iso: fields.iso,
                time: fields.time,
                createdAt: timestamp,
                count: fields.count,
                kinds: fields.kinds,
                groups: fields.groups,
                updatedAt: now
            )
            next[index] = bill
        } else {
            bill = Bill(
                id: UUID().uuidString.lowercased(),
                cents: fields.cents,
                type: fields.type,
                note: fields.note,
                iso: fields.iso,
                time: fields.time,
                createdAt: now,
                count: fields.count,
                kinds: fields.kinds,
                groups: fields.groups,
                updatedAt: now
            )
            next.insert(bill, at: 0)
        }

        if await saveBills(next) {
            lastSavedBillID = bill.id
            selectedMonth = DateHelp.monthStart(entryDate)
            entryOpen = false
            entryEditingID = nil
            entryInput = ""
            entryNote = ""
            entryError = ""
            entryAccumulator = nil
            entryOperator = nil
            entryWaitingForOperand = false
            resetOperatorCycle()
            if !wasEditing {
                clearEntryDraft()
            }
            Haptics.cashCounted()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                if self?.lastSavedBillID == bill.id {
                    self?.lastSavedBillID = nil
                }
            }
        } else {
            entryError = "保存失败，请检查存储空间后重试"
        }
    }

    func pressDigit(_ digit: String) {
        resetOperatorCycle()
        if entryWaitingForOperand {
            entryInput = ""
            entryTrailingDecimal = false
            entryWaitingForOperand = false
        }
        if entryJustEvaluated {
            entryInput = ""
            entryTrailingDecimal = false
            entryJustEvaluated = false
        }
        if entryTrailingDecimal {
            guard digit != "." else { return }
            let fraction = entryInput.split(separator: ".", omittingEmptySubsequences: false).last ?? ""
            guard fraction.count < 2 else { return }
            entryInput += digit
            return
        }
        if digit == "0" && entryInput == "0" { return }
        if entryInput == "0" { entryInput = digit; return }
        entryInput += digit
    }

    func pressDecimal() {
        resetOperatorCycle()
        if entryWaitingForOperand {
            entryInput = ""
            entryTrailingDecimal = false
            entryWaitingForOperand = false
        }
        if entryJustEvaluated {
            entryInput = ""
            entryJustEvaluated = false
        }
        guard !entryInput.contains(".") else { return }
        if entryInput.isEmpty { entryInput = "0" }
        entryInput += "."
        entryTrailingDecimal = true
    }

    func pressDoubleZero() {
        resetOperatorCycle()
        if entryWaitingForOperand {
            entryInput = ""
            entryTrailingDecimal = false
            entryWaitingForOperand = false
        }
        if entryJustEvaluated {
            entryInput = ""
            entryTrailingDecimal = false
            entryJustEvaluated = false
        }
        if entryInput.isEmpty || entryInput == "0" {
            entryInput = "0"
            return
        }
        if entryTrailingDecimal {
            let fraction = entryInput.split(separator: ".", omittingEmptySubsequences: false).last ?? ""
            if fraction.isEmpty { entryInput += "00" }
            else if fraction.count == 1 { entryInput += "0" }
            return
        }
        entryInput += "00"
    }

    func pressBackspace() {
        entryError = ""
        resetOperatorCycle()
        if entryWaitingForOperand {
            entryWaitingForOperand = false
            entryOperator = nil
            if let left = entryAccumulator {
                entryAccumulator = nil
                entryInput = Formats.amountInput(left)
            }
            return
        }
        if entryJustEvaluated {
            entryInput = ""
            entryTrailingDecimal = false
            entryJustEvaluated = false
        }
        if entryInput.isEmpty {
            if let left = entryAccumulator {
                entryAccumulator = nil
                entryOperator = nil
                entryInput = Formats.amountInput(left)
            }
            return
        }
        entryInput.removeLast()
        entryTrailingDecimal = entryInput.last == "."
        if entryInput.isEmpty, entryAccumulator != nil, entryOperator != nil {
            // Keep the expression alive after deleting the right operand:
            // "1+2|" → "1+|" → "1|".
            entryWaitingForOperand = true
        }
    }

    func clearEntry() {
        resetOperatorCycle()
        entryInput = ""
        entryTrailingDecimal = false
        entryJustEvaluated = false
        entryAccumulator = nil
        entryOperator = nil
        entryWaitingForOperand = false
    }

    func cycleOperator() {
        let now = Date().timeIntervalSinceReferenceDate
        let rapid = entryOperatorTapAt != 0 && now - entryOperatorTapAt <= 0.7
        entryOperatorTapIndex = rapid ? (entryOperatorTapIndex + 1) % EntryOperator.allCases.count : 0
        entryOperatorTapAt = now
        selectOperator(EntryOperator.allCases[entryOperatorTapIndex])
    }

    private func resetOperatorCycle() {
        entryOperatorTapIndex = 0
        entryOperatorTapAt = 0
    }

    func selectOperator(_ op: EntryOperator) {
        if let pending = entryOperator, !entryWaitingForOperand, let left = entryAccumulator {
            guard let result = Self.operationResult(left, pending, entryCents) else {
                entryError = "不能除以 0"
                Haptics.warning()
                return
            }
            guard result >= 0 else {
                entryError = "金额不能为负"
                Haptics.warning()
                return
            }
            entryAccumulator = result
            entryInput = Formats.amountInput(result)
        } else if !entryWaitingForOperand {
            entryAccumulator = entryCents
        }
        entryOperator = op
        entryWaitingForOperand = true
        entryTrailingDecimal = false
        entryJustEvaluated = false
    }

    func pressEquals() {
        guard let left = entryAccumulator, let op = entryOperator else { return }
        resetOperatorCycle()
        if entryWaitingForOperand {
            entryInput = Formats.amountInput(left)
        } else {
            guard let result = Self.operationResult(left, op, entryCents) else {
                entryError = "不能除以 0"
                Haptics.warning()
                return
            }
            guard result >= 0 else {
                entryError = "金额不能为负"
                Haptics.warning()
                return
            }
            entryInput = Formats.amountInput(result)
        }
        entryTrailingDecimal = false
        entryAccumulator = nil
        entryOperator = nil
        entryWaitingForOperand = false
        entryJustEvaluated = true
        Haptics.equalsSettle()
    }

    private func finalizeEntryCents() -> Int? {
        var cents = entryCents
        if let left = entryAccumulator, let op = entryOperator {
            if entryWaitingForOperand {
                cents = left
            } else {
                guard let result = Self.operationResult(left, op, entryCents) else {
                    entryError = "不能除以 0"
                    Haptics.warning()
                    return nil
                }
                guard result >= 0 else {
                    entryError = "金额不能为负"
                    Haptics.warning()
                    return nil
                }
                cents = result
                entryInput = Formats.amountInput(result)
            }
            entryAccumulator = nil
            entryOperator = nil
            entryWaitingForOperand = false
            entryTrailingDecimal = false
            entryJustEvaluated = true
        }
        return max(0, cents)
    }

    private static func operationResult(_ left: Int, _ op: EntryOperator, _ right: Int) -> Int? {
        switch op {
        case .add:
            return left + right
        case .subtract:
            return left - right
        case .multiply:
            return Int((Double(left) * Double(right) / 100.0).rounded())
        case .divide:
            guard right != 0 else { return nil }
            return Int((Double(left) * 100.0 / Double(right)).rounded())
        }
    }

    func changeType(_ type: BillType) {
        guard type != entryType else { return }
        entryType = type
        Haptics.pick()
    }

    func confirmDate(_ date: Date) {
        Haptics.pick()
        entryDate = date
        dateSheetOpen = false
    }

    func dismissEntryError() {
        entryError = ""
    }

}

struct DayGroup: Identifiable {
    let iso: String
    let bills: [Bill]
    let expense: Int
    let income: Int

    var id: String { iso }
    var net: Int { income - expense }
    var isToday: Bool { iso == DateHelp.todayISO }
}

enum SampleData {
    static let bills: [Bill] = {
        let now = Date()
        let calendar = Calendar.current
        func iso(_ offset: Int) -> String {
            let date = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            return DateHelp.iso(from: date)
        }
        return [
            Bill(id: "sample-1", cents: 12345, type: .expense, note: "买菜", iso: iso(0), time: "18:20", createdAt: 3_000, count: 4, kinds: 3, groups: []),
            Bill(id: "sample-2", cents: 2800, type: .expense, note: "咖啡", iso: iso(0), time: "14:10", createdAt: 2_000, count: 3, kinds: 2, groups: []),
            Bill(id: "sample-3", cents: 500000, type: .income, note: "项目尾款", iso: iso(0), time: "09:30", createdAt: 1_000, count: 5, kinds: 1, groups: []),
            Bill(id: "sample-4", cents: 4650, type: .expense, note: "打车", iso: iso(-1), time: "21:05", createdAt: 900, count: 4, kinds: 3, groups: []),
            Bill(id: "sample-5", cents: 3200, type: .expense, note: "午饭", iso: iso(-1), time: "12:40", createdAt: 800, count: 3, kinds: 2, groups: [])
        ]
    }()
}

extension Formats {
    static func formattedInput(_ raw: String) -> String {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        var whole = String(parts.first ?? "0")
        var sign = ""
        if whole.hasPrefix("-") {
            sign = "-"
            whole.removeFirst()
        }
        if whole.isEmpty { whole = "0" }
        let grouped = sign + Formats.groupedInteger(whole)
        if parts.count > 1 {
            return grouped + "." + String(parts[1].prefix(2))
        }
        return grouped
    }
}
