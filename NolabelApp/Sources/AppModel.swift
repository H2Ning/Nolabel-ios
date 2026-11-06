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
    private let api = AccountAPI()
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
    private let cacheOwnerKey = "nolabel-cache-owner"
    private let themeKey = "nolabel-theme"
    private let sortKey = "nolabel-sort-desc"
    private let cashModeKey = "nolabel-cash-mode"
    private let plazaStageModeKey = "nolabel-plaza-stage-mode"
    private let hapticKey = "nolabel-haptic-level"
    private let numberFormatKey = "nolabel-number-format"
    private let deleteConfirmKey = "nolabel-delete-confirm"
    private let usernameKey = "h2ning_username"
    private let monthKey = "nolabel-selected-month"
    private let plazaDetentKey = "nolabel-plaza-detent"
    private let draftInputKey = "nolabel-entry-draft-input"
    private let draftNoteKey = "nolabel-entry-draft-note"
    private let draftTypeKey = "nolabel-entry-draft-type"
    private let draftAtKey = "nolabel-entry-draft-at"

    let previewMode: Bool
    let previewProbe: Bool
    var pendingDeleteBill: Bill?
    var deleteConfirmEnabled: Bool {
        didSet { defaults.set(deleteConfirmEnabled, forKey: deleteConfirmKey) }
    }
    private(set) var undoDeleteTitle: String?
    private var deleteUndoSnapshot: [Bill]?
    private var undoTask: Task<Void, Never>?
    var cashPlazaOpen = false

    var bills: [Bill] = [] {
        didSet {
            billsRevision &+= 1
            updateWidgetSnapshot()
        }
    }
    var user: AccountUser?
    var authReady = false
    var authLoading = false
    var accountLoaded = false
    var authMessage = ""
    var authMessageIsError = false
    var authRetryable = false
    var networkDiagnostic = ""

    var themeMode: ThemeMode
    var hapticLevel: HapticLevel
    var appIcon: AppIconChoice
    var numberFormat: NumberFormatSettings
    var sortDesc: Bool
    var selectedMonth: Date {
        didSet {
            defaults.set(selectedMonth, forKey: monthKey)
            updateWidgetSnapshot()
        }
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
    var cashYaw: Double = Double(CashSceneLayout.defaultYaw)
    var cashPitch: Double = Double(CashSceneLayout.packageTilt)
    var cashMode = 1
    var plazaStageMode: Int {
        didSet { defaults.set(plazaStageMode, forKey: plazaStageModeKey) }
    }

    private var bootstrapped = false
    private var autoRetryUsed = false
    private var autoRetryTask: Task<Void, Never>?
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

    var isLoggedIn: Bool { user != nil }

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
        previewProbe = arguments.contains("--preview-probe")
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

        if let raw = BillStore.shared.loadRaw(), let envelope = BillsCodec.parse(raw) {
            bills = envelope.bills
        }

        if previewMode {
            configurePreview(arguments: arguments)
        }
        Formats.apply(numberFormat)
        Haptics.setLevel(hapticLevel)
    }

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        if previewMode {
            authReady = true
            if previewProbe {
                await runNetworkProbe()
            }
            return
        }
        loadCachedBillsIfNeeded()
        await checkAuth()
    }

    /// Shows the last local ledger immediately so the first frame and the
    /// widget do not wait for the account request. The owner check keeps
    /// another account's cache from appearing after a switch.
    private func loadCachedBillsIfNeeded() {
        guard bills.isEmpty else { return }
        guard let local = currentLocalEnvelope(), !local.bills.isEmpty else { return }
        let owner = defaults.string(forKey: cacheOwnerKey)
        let remembered = defaults.string(forKey: usernameKey)
        guard owner == nil || owner == remembered else { return }
        bills = local.bills
    }

    private func configurePreview(arguments: [String]) {
        themeMode = value(after: "--preview-theme", in: arguments).flatMap(ThemeMode.init(rawValue:)) ?? .dark
        bills = SampleData.bills
        authReady = true
        authMessage = ""
        if arguments.contains("--preview-user") {
            user = AccountUser(id: "preview", name: "H2Ning")
            accountLoaded = true
        }

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
        } else if screen == "account" {
            settingsOpen = true
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

    func runNetworkProbe() async {
        authLoading = true
        authMessage = ""
        authMessageIsError = false
        defer { authLoading = false }
        do {
            let user = try await api.me()
            let pin = PinnedTrustDelegate.lastPinUsed ? "，证书固定通过" : ""
            var text = "网络连接正常" + (user.map { "，已登录 \($0.name)" } ?? "，未登录") + pin
            do {
                _ = try await api.fetchBills()
                text += "，账单接口正常"
            } catch AccountError.unauthorized {
                text += "，账单接口正常（未登录）"
            }
            authMessage = text
            authMessageIsError = true
            authRetryable = false
        } catch {
            let reason = (error as? AccountError)?.failureReason ?? error.localizedDescription
            authMessage = "\(error.localizedDescription)｜\(reason)"
            authMessageIsError = true
            authRetryable = true
        }
    }

    func checkAuth() async {
        guard !previewMode else { return }
        authLoading = true
        authMessage = ""
        authMessageIsError = false
        authRetryable = false
        networkDiagnostic = ""
        defer { authLoading = false }
        do {
            let user = try await api.me()
            self.user = user
            authReady = true
            autoRetryUsed = false
            autoRetryTask?.cancel()
            autoRetryTask = nil
            if user != nil {
                await loadAccount()
            } else {
                accountLoaded = false
            }
        } catch {
            user = nil
            authReady = true
            accountLoaded = false
            authMessage = networkMessage(for: error, fallback: "网络错误，暂未连接账号")
            authMessageIsError = true
            authRetryable = (error as? AccountError)?.isNetwork == true
            scheduleAutoRetryIfNeeded()
        }
    }

    func retryConnection() async {
        autoRetryUsed = false
        autoRetryTask?.cancel()
        autoRetryTask = nil
        if user == nil {
            await checkAuth()
        } else {
            await loadAccount()
        }
    }

    func loadAccount() async {
        guard let user else { return }
        authLoading = true
        accountLoaded = false
        authMessage = ""
        authMessageIsError = false
        authRetryable = false
        networkDiagnostic = ""
        defer { authLoading = false }

        do {
            let remote = try await api.fetchBills()
            let local = currentLocalEnvelope()
            let owner = defaults.string(forKey: cacheOwnerKey)
            let localBelongs = owner == nil || owner == user.name

            var result = remote?.bills ?? []
            let remoteCount = result.count

            if localBelongs, let local, !local.bills.isEmpty {
                result = mergeBills(primary: result, secondary: local.bills)
            }

            if result.isEmpty, let local, localBelongs, !local.bills.isEmpty {
                result = local.bills
            }

            if result.count > remoteCount || (remote == nil && !result.isEmpty) {
                try await api.saveBills(result, updatedAt: Date().timeIntervalSince1970 * 1000)
            }

            accountLoaded = true
            bills = result
            persistCache(bills: result, owner: user.name)
            authMessage = ""
            autoRetryUsed = false
            autoRetryTask?.cancel()
            autoRetryTask = nil
        } catch AccountError.unauthorized {
            self.user = nil
            accountLoaded = false
            authMessage = "登录已过期，请重新登录"
            authMessageIsError = true
            authRetryable = false
        } catch {
            accountLoaded = false
            authMessage = networkMessage(for: error, fallback: "账号数据加载失败")
            authMessageIsError = true
            authRetryable = (error as? AccountError)?.isNetwork == true
            scheduleAutoRetryIfNeeded()
        }
    }

    private func networkMessage(for error: Error, fallback: String) -> String {
        guard let accountError = error as? AccountError, accountError.isNetwork else {
            return (error as? LocalizedError)?.errorDescription ?? fallback
        }

        var details: [String] = []
        if let reason = accountError.failureReason {
            details.append(reason)
        }
        let address = AccountAPI.privateNetworkAddress()
        if let address {
            details.append("DNS \(address)")
        }
        networkDiagnostic = details.joined(separator: " · ")

        if let address {
            return "当前网络把 h2ning.com 解析到内网地址 \(address)。请关闭 VPN/Tailscale，或切换 Wi-Fi/蜂窝后重试。"
        }
        return (error as? LocalizedError)?.errorDescription ?? fallback
    }

    private func scheduleAutoRetryIfNeeded() {
        guard authRetryable, !autoRetryUsed, !previewMode else { return }
        autoRetryUsed = true
        autoRetryTask?.cancel()
        autoRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.autoRetryTask = nil
            guard self.authMessageIsError, !self.authLoading else { return }
            if self.user == nil {
                await self.checkAuth()
            } else {
                await self.loadAccount()
            }
        }
    }

    private func currentLocalEnvelope() -> BillsEnvelope? {
        guard let raw = BillStore.shared.loadRaw() else { return nil }
        return BillsCodec.parse(raw)
    }

    private func mergeBills(primary: [Bill], secondary: [Bill]) -> [Bill] {
        var map: [String: Bill] = [:]
        for bill in secondary { map[bill.id] = bill }
        for bill in primary { map[bill.id] = bill }
        return map.values.sorted { $0.createdAt > $1.createdAt }
    }

    private func persistCache(bills: [Bill], owner: String?) {
        let raw = BillsCodec.raw(bills, updatedAt: Date().timeIntervalSince1970 * 1000)
        BillStore.shared.saveRaw(raw)
        if let owner {
            defaults.set(owner, forKey: cacheOwnerKey)
        } else {
            defaults.removeObject(forKey: cacheOwnerKey)
        }
    }

    private func clearCache() {
        BillStore.shared.saveRaw(BillsCodec.raw([], updatedAt: Date().timeIntervalSince1970 * 1000))
        defaults.removeObject(forKey: cacheOwnerKey)
    }

    func login(username: String, password: String) async {
        guard !username.isEmpty, !password.isEmpty else {
            authMessage = "请输入用户名和密码"
            authMessageIsError = true
            return
        }
        authLoading = true
        authMessage = ""
        authMessageIsError = false
        authRetryable = false
        networkDiagnostic = ""
        defer { authLoading = false }
        do {
            let user = try await api.login(username: username, password: password)
            self.user = user
            defaults.set(username, forKey: usernameKey)
            authReady = true
            autoRetryUsed = false
            autoRetryTask?.cancel()
            autoRetryTask = nil
            Haptics.success()
            await loadAccount()
        } catch {
            authMessage = networkMessage(for: error, fallback: "登录失败")
            authMessageIsError = true
            authRetryable = (error as? AccountError)?.isNetwork == true
            Haptics.error()
            if authRetryable, !autoRetryUsed {
                autoRetryUsed = true
                autoRetryTask?.cancel()
                autoRetryTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    guard let self, !Task.isCancelled else { return }
                    self.autoRetryTask = nil
                    guard self.authMessageIsError, !self.authLoading else { return }
                    await self.login(username: username, password: password)
                }
            }
        }
    }

    func logout() async {
        authLoading = true
        defer { authLoading = false }
        do {
            try await api.logout()
        } catch {
            // The local session is cleared even when the server is unreachable.
        }
        user = nil
        accountLoaded = false
        authReady = true
        bills = []
        clearCache()
        VerdictSnapshot.clear()
        authMessage = ""
        authMessageIsError = false
        settingsSubview = .main
    }

    var savedUsername: String {
        defaults.string(forKey: usernameKey) ?? ""
    }

    @discardableResult
    func requireLogin() -> Bool {
        if previewMode { return true }
        guard user != nil, accountLoaded else {
            authMessage = user == nil ? "请先在设置登录账号" : "账号数据还没加载好"
            authMessageIsError = true
            settingsOpen = true
            settingsSubview = .main
            return false
        }
        return true
    }

    func saveBills(_ next: [Bill]) async -> Bool {
        guard requireLogin() else { return false }
        writing = true
        defer { writing = false }
        do {
            try await api.saveBills(next, updatedAt: Date().timeIntervalSince1970 * 1000)
            bills = next
            if let user { persistCache(bills: next, owner: user.name) }
            return true
        } catch AccountError.unauthorized {
            user = nil
            accountLoaded = false
            authMessage = "登录已过期，请重新登录"
            authMessageIsError = true
            authRetryable = false
            settingsOpen = true
            Haptics.error()
            return false
        } catch {
            authMessage = networkMessage(for: error, fallback: "保存失败，请检查网络后重试")
            authMessageIsError = true
            authRetryable = (error as? AccountError)?.isNetwork == true
            Haptics.error()
            return false
        }
    }

    func requestDelete(_ bill: Bill) {
        guard requireLogin() else { return }
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
        guard requireLogin() else { return }
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

    /// Mirrors the selected month's verdict into the widget's shared store.
    func updateWidgetSnapshot() {
        // A failed launch must not replace a good snapshot with an empty one.
        if bills.isEmpty, !accountLoaded, VerdictSnapshot.load() != nil { return }
        let month = DateHelp.monthStart(selectedMonth)
        let analysis = MonthAnalysis(bills: monthBills, month: month)
        let metricLabel: String
        let amountText: String
        let countLabel: String
        if analysis.expenseTotal > 0 {
            metricLabel = "支出"
            amountText = Formats.moneyValue(analysis.expenseTotal)
            countLabel = "共 \(analysis.expenseCount) 笔"
        } else if analysis.incomeTotal > 0 {
            metricLabel = "收入"
            amountText = Formats.moneyValue(analysis.incomeTotal)
            countLabel = "共 \(analysis.incomeCount) 笔"
        } else {
            metricLabel = "该月"
            amountText = Formats.moneyValue(0)
            countLabel = "还没有账单"
        }
        let snapshot = VerdictSnapshot(
            monthISO: VerdictSnapshot.currentMonthISO(month),
            monthLabel: VerdictSnapshot.currentMonthLabel(month),
            verdictTitle: analysis.verdict.title,
            metricLabel: metricLabel,
            amountText: amountText,
            countLabel: countLabel
        )
        guard VerdictSnapshot.load() != snapshot else { return }
        snapshot.save()
    }

    /// Opens the plaza on the month the widget is showing.
    func openVerdictFromWidget() {
        if let month = VerdictSnapshot.load()?.monthStart {
            selectedMonth = DateHelp.monthStart(month)
        }
        openBillID = nil
        cashPlazaOpen = true
        plazaDetent = .medium
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

    /// Deletes every bill locally and on the server. The caller must confirm
    /// first; this only performs the write.
    @discardableResult
    func clearAllBills() async -> Bool {
        guard requireLogin() else { return false }
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
        guard requireLogin() else { return false }
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
                authMessage = ""
                authMessageIsError = false
                Haptics.success()
                return true
            }
            return false
        } catch {
            authMessage = (error as? LocalizedError)?.errorDescription ?? "CSV 读取失败"
            authMessageIsError = true
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
        updateWidgetSnapshot()
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
        cashYaw = Double(CashSceneLayout.defaultYaw)
        cashPitch = Double(CashSceneLayout.packageTilt)
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
        guard requireLogin() else {
            entryError = "请先在设置登录账号"
            Haptics.warning()
            return
        }

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
            let timestamp = previous.iso == iso && previous.time == time ? previous.createdAt : entryDate.timeIntervalSince1970 * 1000
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
                groups: fields.groups
            )
            next[index] = bill
        } else {
            bill = Bill(
                id: "\(Int(Date().timeIntervalSince1970 * 1000))\(UUID().uuidString.prefix(4))",
                cents: fields.cents,
                type: fields.type,
                note: fields.note,
                iso: fields.iso,
                time: fields.time,
                createdAt: Date().timeIntervalSince1970 * 1000,
                count: fields.count,
                kinds: fields.kinds,
                groups: fields.groups
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
            entryError = settingsOpen ? "登录已过期，请重新登录" : "保存失败，请检查网络后重试"
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
