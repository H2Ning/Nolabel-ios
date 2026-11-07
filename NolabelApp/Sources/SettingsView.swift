import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsPage: View {
    let sub: SettingsSubview
    @Bindable var model: AppModel
    let palette: AppPalette
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var showClearAllConfirm = false
    @State private var iconToast: String?
    @State private var iconToastTask: Task<Void, Never>?
    @State private var iconSwitching = false

    var body: some View {
        ZStack {
            palette.pageBG.ignoresSafeArea()
            settingsAtmosphere
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch sub {
                    case .main:
                        mainView
                    case .personalization:
                        personalizationView
                    case .appearance:
                        appearanceView
                    case .icon:
                        iconView
                    case .numberFormat:
                        numberFormatView
                    case .haptics:
                        hapticsView
                    case .dataSecurity:
                        dataSecurityView
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if let iconToast {
                Text(iconToast)
                    .scalableFont(14, weight: .medium)
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 46)
                    .background(palette.surface, in: Capsule())
                    .overlay(Capsule().stroke(palette.line, lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: iconToast)
        .navigationTitle(settingsTitle)
        .navigationBarTitleDisplayMode(sub == .main ? .large : .inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url),
                      let text = String(data: data, encoding: .utf8) else {
                    model.dataMessage = "CSV 文件读取失败"
                    model.dataMessageIsError = true
                    return
                }
                Task { await model.importCSV(text) }
            case .failure:
                model.dataMessage = "CSV 文件读取失败"
                model.dataMessageIsError = true
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: CSVDocument(text: model.csvExportText),
            contentType: .commaSeparatedText,
            defaultFilename: "Nolabel-\(DateHelp.todayISO).csv"
        ) { result in
            if case .failure = result {
                model.dataMessage = "CSV 文件导出失败"
                model.dataMessageIsError = true
                Haptics.error()
            } else {
                Haptics.success()
            }
        }
        .alert("清空全部账单？", isPresented: $showClearAllConfirm) {
            Button("取消", role: .cancel) {
                Haptics.soft()
            }
            Button("清空全部", role: .destructive) {
                Task { await model.clearAllBills() }
            }
        } message: {
            Text("将删除全部 \(model.bills.count) 笔账单，只影响本机数据。此操作无法撤销。")
        }
    }

    private var settingsAtmosphere: some View {
        RadialGradient(
            colors: [
                palette.isDark
                    ? Color(hex: 0x22372A).opacity(0.65)
                    : Color.white.opacity(0.70),
                .clear
            ],
            center: UnitPoint(x: 0.5, y: -0.08),
            startRadius: 0,
            endRadius: 430
        )
    }

    private var mainView: some View {
        VStack(spacing: 12) {
            sectionCard {
                settingsNavLink(title: "外观") {
                    model.pushSettings(.appearance)
                }
                divider
                settingsNavLink(title: "个性化") {
                    model.pushSettings(.personalization)
                }
            }
            sectionCard {
                settingsNavLink(title: "数据与安全") {
                    model.pushSettings(.dataSecurity)
                }
            }
            Text(alphaVersionLabel)
                .scalableFont(11, weight: .regular)
                .foregroundStyle(palette.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    private var alphaVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Alpha \(version)（build \(build)）"
    }

    private var settingsTitle: String {
        switch sub {
        case .main: return "设置"
        case .personalization: return "个性化"
        case .appearance: return "外观"
        case .icon: return "图标"
        case .numberFormat: return "数字格式"
        case .haptics: return "触感"
        case .dataSecurity: return "数据与安全"
        }
    }

    private var appearanceView: some View {
        sectionCard {
            ForEach(Array(ThemeMode.allCases.enumerated()), id: \.element) { index, mode in
                Button {
                    model.setTheme(mode)
                } label: {
                    HStack {
                        Text(mode.label)
                            .scalableFont(16, weight: .medium)
                            .foregroundStyle(palette.ink)
                        Spacer()
                        if model.themeMode == mode {
                            Image(systemName: "checkmark")
                                .scalableFont(14, weight: .semibold)
                                .foregroundStyle(palette.accent)
                        }
                    }
                    .frame(minHeight: 54)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < ThemeMode.allCases.count - 1 {
                    divider
                }
            }
        }
    }

    private var numberFormatView: some View {
        VStack(spacing: 14) {
            previewCard
            billTimeCard
            formatCard
            colorCard
            currencyCard
        }
    }

    private struct PreviewBill: Identifiable {
        let id: String
        let title: String
        let cents: Int
        let type: BillType
        let time: String
    }

    private var previewBills: [PreviewBill] {
        [
            PreviewBill(id: "preview-lottery", title: "中彩票", cents: 1_234_567, type: .income, time: "09:30"),
            PreviewBill(id: "preview-rent", title: "房租", cents: 123_456, type: .expense, time: "18:20")
        ]
    }

    private var previewCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(DateHelp.dayTitle(DateHelp.todayISO))
                    .scalableFont(13, weight: .semibold)
                    .foregroundStyle(palette.ink2)
                Spacer(minLength: 8)
                Text("今天")
                    .scalableFont(11, weight: .semibold)
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(palette.accentSoft, in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 9)
            .background(palette.surface2.opacity(palette.isDark ? 0.55 : 0.62))

            ForEach(Array(previewBills.enumerated()), id: \.element.id) { index, bill in
                previewBillRow(bill)
                if index < previewBills.count - 1 {
                    divider
                }
            }
        }
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
        .shadow(color: palette.isDark ? .black.opacity(0.12) : .black.opacity(0.06), radius: 12, y: 8)
    }

    private func previewBillRow(_ bill: PreviewBill) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(bill.type == .expense ? palette.expense : palette.income)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: model.showBillTime ? 4 : 0) {
                Text(bill.title)
                    .scalableFont(16, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                if model.showBillTime, !bill.time.isEmpty {
                    Text(bill.time)
                        .scalableFont(12, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(Formats.signedMoney(bill.cents, type: bill.type))
                .scalableFont(16, weight: .semibold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(bill.type == .expense ? palette.expense : palette.income)
                .lineLimit(1)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.vertical, 13)
    }

    private var billTimeCard: some View {
        sectionCard {
            Toggle(isOn: $model.showBillTime) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("账单条显示时间")
                        .scalableFont(16, weight: .medium)
                        .foregroundStyle(palette.ink)
                    Text("关闭后，备注居中显示")
                        .scalableFont(11, weight: .regular)
                        .foregroundStyle(palette.muted)
                }
            }
            .tint(palette.accent)
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
        }
    }

    private var formatCard: some View {
        VStack(spacing: 0) {
            formatRow(title: "收入格式") {
                Picker("收入格式", selection: incomeFormatBinding) {
                    ForEach(IncomeFormat.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            }
            formatDivider
            formatRow(title: "支出格式") {
                Picker("支出格式", selection: expenseFormatBinding) {
                    ForEach(ExpenseFormat.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            }
            formatDivider
            formatRow(title: "分隔符") {
                Menu {
                    ForEach(AmountSeparator.allCases) { option in
                        Button {
                            model.updateNumberFormat { $0.separator = option }
                        } label: {
                            if model.numberFormat.separator == option {
                                Label(option.summaryLabel, systemImage: "checkmark")
                            } else {
                                Text(option.summaryLabel)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(model.numberFormat.separator.summaryLabel)
                        Image(systemName: "chevron.up.chevron.down")
                            .scalableFont(9, weight: .semibold)
                    }
                    .scalableFont(15, weight: .medium)
                    .foregroundStyle(palette.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
            }
        }
        .background(sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }

    private var incomeFormatBinding: Binding<IncomeFormat> {
        Binding(
            get: { model.numberFormat.incomeFormat },
            set: { value in model.updateNumberFormat { $0.incomeFormat = value } }
        )
    }

    private var expenseFormatBinding: Binding<ExpenseFormat> {
        Binding(
            get: { model.numberFormat.expenseFormat },
            set: { value in model.updateNumberFormat { $0.expenseFormat = value } }
        )
    }

    private func formatRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .scalableFont(13, weight: .semibold)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            content()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
    }

    private var formatDivider: some View {
        Rectangle()
            .fill(palette.line)
            .frame(height: 1)
            .padding(.horizontal, 12)
    }

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("收支配色")
                .scalableFont(14, weight: .semibold)
                .foregroundStyle(palette.ink)

            HStack(spacing: 8) {
                ForEach(NumberColorScheme.allCases) { scheme in
                    colorOption(scheme)
                }
            }
        }
        .padding(16)
        .background(sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }

    private func colorOption(_ scheme: NumberColorScheme) -> some View {
        let selected = model.numberFormat.colorScheme == scheme
        return Button {
            withAnimation(AppMotion.grace) {
                model.updateNumberFormat { $0.colorScheme = scheme }
            }
        } label: {
            VStack(spacing: 7) {
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: AppRadius.micro, style: .continuous)
                        .fill(scheme.incomeColor(isDark: palette.isDark))
                    RoundedRectangle(cornerRadius: AppRadius.micro, style: .continuous)
                        .fill(scheme.expenseColor(isDark: palette.isDark))
                }
                .frame(height: 38)

                Text(scheme.label)
                    .scalableFont(10, weight: .semibold)
                    .foregroundStyle(selected ? palette.accent : palette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                    .fill(selected ? palette.accentSoft : palette.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                    .stroke(selected ? palette.accent.opacity(0.55) : palette.line, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark")
                        .scalableFont(8, weight: .black)
                        .foregroundStyle(palette.accentInk)
                        .frame(width: 14, height: 14)
                        .background(palette.accent, in: Circle())
                        .offset(x: 3, y: -3)
                }
            }
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .accessibilityLabel(scheme.label)
        .accessibilityValue(selected ? "已选择" : "")
    }

    private var currencyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("货币符号")
                .scalableFont(14, weight: .semibold)
                .foregroundStyle(palette.ink)

            HStack(spacing: 8) {
                ForEach(CurrencySymbol.allCases) { currency in
                    currencyOption(currency)
                }
            }
        }
        .padding(16)
        .background(sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }

    /// Mirrors the income/expense color chips, but the swatch is a single
    /// engraved coin so the currency mark reads as designed, not as a glyph.
    private func currencyOption(_ currency: CurrencySymbol) -> some View {
        let selected = model.numberFormat.currency == currency
        return Button {
            withAnimation(AppMotion.grace) {
                model.updateNumberFormat { $0.currency = currency }
            }
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(selected ? palette.accentSoft : palette.surface)
                    Circle()
                        .stroke(selected ? palette.accent.opacity(0.55) : palette.lineStrong, lineWidth: 1)
                    Circle()
                        .stroke(selected ? palette.accent.opacity(0.22) : palette.line.opacity(0.7), lineWidth: 0.7)
                        .padding(3.5)
                    Text(currency.symbol)
                        .scalableFont(19, weight: .bold, design: .serif)
                        .foregroundStyle(selected ? palette.accent : palette.ink2)
                }
                .frame(width: 38, height: 38)

                Text(currency.label)
                    .scalableFont(10, weight: .semibold)
                    .foregroundStyle(selected ? palette.accent : palette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                    .fill(selected ? palette.accentSoft : palette.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                    .stroke(selected ? palette.accent.opacity(0.55) : palette.line, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark")
                        .scalableFont(8, weight: .black)
                        .foregroundStyle(palette.accentInk)
                        .frame(width: 14, height: 14)
                        .background(palette.accent, in: Circle())
                        .offset(x: 3, y: -3)
                }
            }
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .accessibilityLabel("\(currency.label) \(currency.symbol)")
        .accessibilityValue(selected ? "已选择" : "")
    }

    private var hapticsView: some View {
        sectionCard {
            ForEach(Array(HapticLevel.allCases.enumerated()), id: \.element) { index, level in
                Button {
                    model.setHapticLevel(level)
                } label: {
                    HStack {
                        Text(level.label)
                            .scalableFont(16, weight: .medium)
                            .foregroundStyle(palette.ink)
                        Spacer()
                        if model.hapticLevel == level {
                            Image(systemName: "checkmark")
                                .scalableFont(14, weight: .semibold)
                                .foregroundStyle(palette.accent)
                        }
                    }
                    .frame(minHeight: 54)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < HapticLevel.allCases.count - 1 {
                    divider
                }
            }
        }
    }

    private var sectionBackground: Color {
        palette.surface2.opacity(palette.isDark ? 0.56 : 0.60)
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.line)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }

    private var personalizationView: some View {
        sectionCard {
            Button {
                model.pushSettings(.icon)
            } label: {
                HStack(spacing: 10) {
                    Text("图标")
                        .scalableFont(16, weight: .medium)
                        .foregroundStyle(palette.ink)
                    Spacer(minLength: 8)
                    Image(model.appIcon.previewName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(palette.line, lineWidth: 0.8)
                        )
                        .accessibilityHidden(true)
                    Image(systemName: "chevron.right")
                        .scalableFont(13, weight: .semibold)
                        .foregroundStyle(palette.muted)
                }
                .frame(minHeight: 56)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("图标")
            .accessibilityValue(model.appIcon.displayName)
            divider
            settingsLink(title: "格式", value: model.numberFormat.summary) {
                model.pushSettings(.numberFormat)
            }
            divider
            settingsLink(title: "触感", value: model.hapticLevel.label) {
                model.pushSettings(.haptics)
            }
        }
    }

    private var dataSecurityView: some View {
        VStack(spacing: 14) {
            sectionCard {
                Toggle(isOn: $model.deleteConfirmEnabled) {
                    Text("删除前确认")
                        .scalableFont(16, weight: .medium)
                        .foregroundStyle(palette.ink)
                }
                .tint(palette.accent)
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
            }

            Text("诺诺Nolabel是一款单机App，所有账单数据均存储在您的本地设备中。请注意，卸载App会导致您的所有数据丢失。我们不会获取您的任何数据，也无法对您的数据进行恢复。建议您及时通过「账单导出」备份数据。")
                .scalableFont(12, weight: .regular)
                .foregroundStyle(palette.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            if model.dataMessageIsError && !model.dataMessage.isEmpty {
                Text(model.dataMessage)
                    .scalableFont(12, weight: .medium)
                    .foregroundStyle(palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            sectionCard {
                settingsAction(title: "账单导入") { showImporter = true }
                divider
                settingsAction(title: "账单导出") { showExporter = true }
                    .disabled(model.bills.isEmpty)
                    .opacity(model.bills.isEmpty ? 0.45 : 1)
            }
            sectionCard {
                Button {
                    Haptics.deletePrompt()
                    showClearAllConfirm = true
                } label: {
                    HStack {
                        Text("清空全部账单")
                            .scalableFont(16, weight: .medium)
                            .foregroundStyle(palette.danger)
                        Spacer()
                        Text("\(model.bills.count) 笔")
                            .scalableFont(15, weight: .medium)
                            .foregroundStyle(palette.muted)
                    }
                    .frame(minHeight: 54)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.bills.isEmpty)
                .opacity(model.bills.isEmpty ? 0.45 : 1)
                .accessibilityLabel("清空全部账单")
                .accessibilityHint("会先弹出确认，确认后删除全部 \(model.bills.count) 笔账单")
            }
        }
    }

    private var iconView: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
            spacing: 14
        ) {
            ForEach(AppIconChoice.displayOrder) { choice in
                iconCell(choice)
            }
        }
        .padding(14)
        .background(sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }

    private func iconCell(_ choice: AppIconChoice) -> some View {
        let selected = model.appIcon == choice
        return Button {
            selectIcon(choice)
        } label: {
            Image(choice.previewName)
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(selected ? palette.accent : palette.line.opacity(0.7), lineWidth: selected ? 3 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark")
                            .scalableFont(8, weight: .black)
                            .foregroundStyle(palette.accentInk)
                            .frame(width: 18, height: 18)
                            .background(palette.accent, in: Circle())
                            .overlay(Circle().stroke(palette.pageBG, lineWidth: 1.5))
                            .offset(x: 5, y: -5)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel("\(choice.displayName)图标")
        .accessibilityValue(selected ? "已选择" : "")
    }

    private func selectIcon(_ choice: AppIconChoice) {
        guard !iconSwitching else { return }
        iconSwitching = true
        Task { @MainActor in
            let switched = await model.setAppIcon(choice)
            iconSwitching = false
            showIconToast(switched ? "图标已更改" : "图标切换失败")
        }
    }

    private func showIconToast(_ text: String) {
        withAnimation(AppMotion.spring) { iconToast = text }
        iconToastTask?.cancel()
        iconToastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) { iconToast = nil }
        }
    }

    private func settingsNavLink(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .scalableFont(16, weight: .medium)
                    .foregroundStyle(palette.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .scalableFont(13, weight: .semibold)
                    .foregroundStyle(palette.muted)
            }
            .frame(minHeight: 56)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func settingsLink(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .scalableFont(16, weight: .medium)
                    .foregroundStyle(palette.ink)
                Spacer()
                Text(value)
                    .scalableFont(15, weight: .medium)
                    .foregroundStyle(palette.muted)
                Image(systemName: "chevron.right")
                    .scalableFont(13, weight: .semibold)
                    .foregroundStyle(palette.muted)
            }
            .frame(minHeight: 56)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func settingsAction(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .scalableFont(16, weight: .medium)
                    .foregroundStyle(palette.ink)
                Spacer()
            }
            .frame(minHeight: 54)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}
