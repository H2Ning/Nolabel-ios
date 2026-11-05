import Foundation
import Observation
import SwiftUI
import UIKit

enum SettingsSubview {
    case main
    case appearance
    case numberFormat
    case haptics
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
    private let cacheOwnerKey = "nolabel-cache-owner"
    private let themeKey = "nolabel-theme"
    private let sortKey = "nolabel-sort-desc"
    private let cashModeKey = "nolabel-cash-mode"
    private let hapticKey = "nolabel-haptic-level"
    private let numberFormatKey = "nolabel-number-format"
    private let deleteSuppressKey = "nolabel-delete-suppress-date"
    private let usernameKey = "h2ning_username"

    let previewMode: Bool
    let previewProbe: Bool
    var pendingDeleteBill: Bill?
    var cashPlazaOpen = false

    var bills: [Bill] = [] {
        didSet { billsRevision &+= 1 }
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
    var numberFormat: NumberFormatSettings
    var sortDesc: Bool
    var selectedMonth: Date
    var settingsOpen = false
    var settingsSubview: SettingsSubview = .main
    var openBillID: String?
    var lastSavedBillID: String?
    var writing = false

    var entryOpen = false
    var entryEditingID: String?
    var entryInput = ""
    var entryTrailingDecimal = false
    var entryJustEvaluated = false
    var entryType: BillType = .expense
    var entryNote = ""
    var entryDate = Date()
    var entryAccumulator: Int?
    var entryOperator: EntryOperator?
    var entryWaitingForOperand = false
    var dateSheetOpen = false
    var entryError = ""
    var cashYaw: Double = Double(CashSceneLayout.defaultYaw)
    var cashPitch: Double = Double(CashSceneLayout.packageTilt)
    var cashMode = 1

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
        if let data = defaults.data(forKey: numberFormatKey),
           let stored = try? JSONDecoder().decode(NumberFormatSettings.self, from: data) {
            numberFormat = stored
        } else {
            numberFormat = NumberFormatSettings()
        }
        sortDesc = defaults.object(forKey: sortKey) as? Bool ?? true
        let storedCashMode = defaults.integer(forKey: cashModeKey)
        cashMode = (1...3).contains(storedCashMode) ? storedCashMode : 1
        selectedMonth = DateHelp.monthStart(Date())

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
        await checkAuth()
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                guard let self else { return }
                withAnimation(AppMotion.spring) { self.openEntry(self.bills.first) }
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

            bills = result
            accountLoaded = true
            selectedMonth = DateHelp.monthStart(Date())
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

    var deleteConfirmationSuppressedToday: Bool {
        defaults.string(forKey: deleteSuppressKey) == DateHelp.todayISO
    }

    func requestDelete(_ bill: Bill) {
        guard requireLogin() else { return }
        if deleteConfirmationSuppressedToday {
            Haptics.deleteConfirm()
            Task { await delete(bill) }
        } else {
            pendingDeleteBill = bill
            Haptics.deletePrompt()
        }
    }

    func cancelDeletePrompt() {
        pendingDeleteBill = nil
        Haptics.soft()
    }

    func confirmDeletePrompt(suppressToday: Bool) {
        guard let bill = pendingDeleteBill else { return }
        pendingDeleteBill = nil
        if suppressToday {
            defaults.set(DateHelp.todayISO, forKey: deleteSuppressKey)
        }
        Haptics.deleteConfirm()
        Task { await delete(bill) }
    }

    func delete(_ bill: Bill) async {
        guard requireLogin() else { return }
        let next = bills.filter { $0.id != bill.id }
        if await saveBills(next) {
            openBillID = nil
        }
    }

    func shiftMonth(_ value: Int) {
        let previousYear = Calendar.current.component(.year, from: selectedMonth)
        selectedMonth = DateHelp.shiftMonth(selectedMonth, by: value)
        let nextYear = Calendar.current.component(.year, from: selectedMonth)
        Haptics.monthShift(crossesYear: previousYear != nextYear)
    }

    func cycleCashMode() {
        cashMode = cashMode % 3 + 1
        defaults.set(cashMode, forKey: cashModeKey)
        Haptics.cashMode(cashMode)
    }

    var csvExportText: String {
        CSVCodec.csv(for: bills)
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

    func setHapticLevel(_ value: HapticLevel) {
        guard value != hapticLevel else { return }
        hapticLevel = value
        defaults.set(value.rawValue, forKey: hapticKey)
        Haptics.setLevel(value)
        Haptics.pick()
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
        entryOpen = false
        entryEditingID = nil
        entryInput = ""
        entryNote = ""
        entryError = ""
        entryOperator = nil
        entryAccumulator = nil
        entryWaitingForOperand = false
        resetOperatorCycle()
        Haptics.soft()
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
        guard requireLogin() else { return }

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
            Haptics.cashCounted()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                if self?.lastSavedBillID == bill.id {
                    self?.lastSavedBillID = nil
                }
            }
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
