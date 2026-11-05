import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsOverlay: View {
    @Bindable var model: AppModel
    let palette: AppPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var username = ""
    @State private var password = ""
    @State private var showImporter = false
    @State private var showExporter = false
    @FocusState private var focusedField: Field?

    private enum Field { case username, password }

    var body: some View {
        ZStack {
            palette.pageBG.ignoresSafeArea()
            settingsAtmosphere
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    pageHeader

                    Text(settingsTitle)
                        .font(.system(size: 36, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(palette.ink)
                        .padding(.bottom, 2)

                    if model.settingsSubview == .main {
                        mainView
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    } else if model.settingsSubview == .appearance {
                        appearanceView
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    } else if model.settingsSubview == .numberFormat {
                        numberFormatView
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    } else {
                        hapticsView
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(backSwipe)
        .onAppear {
            username = model.savedUsername
        }
        .animation(reduceMotion ? nil : AppMotion.spring, value: model.settingsSubview)
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
                    model.authMessage = "CSV 文件读取失败"
                    model.authMessageIsError = true
                    return
                }
                Task { await model.importCSV(text) }
            case .failure:
                model.authMessage = "CSV 文件读取失败"
                model.authMessageIsError = true
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: CSVDocument(text: model.csvExportText),
            contentType: .commaSeparatedText,
            defaultFilename: "Nolabel-\(DateHelp.todayISO).csv"
        ) { result in
            if case .failure = result {
                model.authMessage = "CSV 文件导出失败"
                model.authMessageIsError = true
                Haptics.error()
            } else {
                Haptics.success()
            }
        }
    }

    private var pageHeader: some View {
        HStack {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.ink2)
                    .frame(width: 46, height: 46)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .glassCircle()
            .accessibilityLabel(model.settingsSubview == .main ? "关闭设置" : "返回设置")
            Spacer(minLength: 0)
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

    private var backSwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard value.startLocation.x < 28,
                      value.translation.width > 90,
                      abs(value.translation.width) > abs(value.translation.height) else {
                    return
                }
                goBack()
            }
    }

    private func goBack() {
        if model.settingsSubview == .main {
            model.closeSettings()
            return
        }
        Haptics.soft()
        withAnimation(AppMotion.spring) {
            model.settingsSubview = .main
        }
    }

    private var mainView: some View {
        VStack(spacing: 12) {
            accountCard
            sectionCard {
                settingsLink(title: "外观", value: model.themeMode.label) {
                    withAnimation(AppMotion.spring) { model.settingsSubview = .appearance }
                }
                divider
                settingsLink(title: "数字格式", value: model.numberFormat.summary) {
                    withAnimation(AppMotion.spring) { model.settingsSubview = .numberFormat }
                }
                divider
                settingsLink(title: "触感", value: model.hapticLevel.label) {
                    withAnimation(AppMotion.spring) { model.settingsSubview = .haptics }
                }
            }
            if model.user != nil && model.accountLoaded {
                sectionCard {
                    settingsAction(title: "账单导入") { showImporter = true }
                    divider
                    settingsAction(title: "账单导出") { showExporter = true }
                        .disabled(model.bills.isEmpty)
                        .opacity(model.bills.isEmpty ? 0.45 : 1)
                }
            }
            if model.authMessageIsError && !model.authMessage.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(model.authMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if model.authRetryable {
                            Button {
                                if !username.isEmpty && !password.isEmpty {
                                    submitLogin()
                                } else {
                                    Task { await model.retryConnection() }
                                }
                            } label: {
                                if model.authLoading {
                                    ProgressView().tint(palette.danger)
                                } else {
                                    Text("重试")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(palette.danger)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(model.authLoading)

                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    openURL(url)
                                }
                            } label: {
                                Text("设置")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(palette.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !model.networkDiagnostic.isEmpty {
                        Text(model.networkDiagnostic)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.muted)
                    }

                    if model.authRetryable {
                        Text("已允许仍失败：设置 → 蜂窝网络 → 诺诺 → 无线局域网与蜂窝移动数据；或 设置 → 隐私与安全性 → 本地网络 → 诺诺。若开着 VPN/Tailscale 或 Wi-Fi 代理，请先关闭或改用蜂窝数据。")
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.authReady {
                HStack(spacing: 10) {
                    ProgressView().tint(palette.ink2)
                    Text("正在连接账号")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            } else if let user = model.user {
                HStack(spacing: 11) {
                    Text(String(user.name.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.accentInk)
                        .frame(width: 36, height: 36)
                        .background(palette.accent, in: Circle())
                    Text(user.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Spacer()
                    if model.authLoading {
                        ProgressView().tint(palette.muted)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 15)
                .padding(.bottom, 12)

                divider

                Button {
                    Task { await model.logout() }
                } label: {
                    Text("退出登录")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 54)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.authLoading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("用户名")
                    TextField("用户名", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, 13)
                        .frame(height: 46)
                        .background(fieldBackground)

                    fieldLabel("密码")
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { submitLogin() }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, 13)
                        .frame(height: 46)
                        .background(fieldBackground)

                    Button(action: submitLogin) {
                        Group {
                            if model.authLoading {
                                ProgressView().tint(palette.accentInk)
                            } else {
                                Text("登录")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .foregroundStyle(palette.accentInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(palette.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    .disabled(model.authLoading)
                }
                .padding(16)
            }
        }
        .background(sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }

    private var settingsTitle: String {
        switch model.settingsSubview {
        case .main: return "设置"
        case .appearance: return "外观"
        case .numberFormat: return "数字格式"
        case .haptics: return "触感"
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
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(palette.ink)
                        Spacer()
                        if model.themeMode == mode {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(palette.accent)
                        }
                    }
                    .frame(height: 54)
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
            formatCard
            colorCard
        }
    }

    private var previewCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("预览")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .padding(.bottom, 10)

            previewRow(cents: 1_234_567, type: .income, title: "尾款", time: "09:30")
            divider
            previewRow(cents: 123_456, type: .expense, title: "房租", time: "18:20")
        }
        .background(sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }

    private func previewRow(cents: Int, type: BillType, title: String, time: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(type == .expense ? palette.expense : palette.income)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text("\(DateHelp.dayTitle(DateHelp.todayISO)) · \(time)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.muted)
            }

            Spacer(minLength: 8)

            Text(Formats.signedMoney(cents, type: type))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(type == .expense ? palette.expense : palette.income)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var formatCard: some View {
        VStack(spacing: 0) {
            formatRow(title: "收入格式") {
                SegmentPicker(
                    options: IncomeFormat.allCases,
                    selection: model.numberFormat.incomeFormat,
                    palette: palette,
                    label: { $0.label }
                ) { value in
                    model.updateNumberFormat { $0.incomeFormat = value }
                }
            }
            formatDivider
            formatRow(title: "支出格式") {
                SegmentPicker(
                    options: ExpenseFormat.allCases,
                    selection: model.numberFormat.expenseFormat,
                    palette: palette,
                    label: { $0.label }
                ) { value in
                    model.updateNumberFormat { $0.expenseFormat = value }
                }
            }
            formatDivider
            formatRow(title: "分隔符") {
                SegmentPicker(
                    options: AmountSeparator.allCases,
                    selection: model.numberFormat.separator,
                    palette: palette,
                    label: { $0.label }
                ) { value in
                    model.updateNumberFormat { $0.separator = value }
                }
            }
        }
        .background(sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }

    private func formatRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            content()
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.ink)

            HStack(spacing: 8) {
                ForEach(NumberColorScheme.allCases) { scheme in
                    colorOption(scheme)
                }
            }
        }
        .padding(16)
        .background(sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
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
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(scheme.incomeColor(isDark: palette.isDark))
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(scheme.expenseColor(isDark: palette.isDark))
                }
                .frame(height: 38)

                Text(scheme.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selected ? palette.accent : palette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? palette.accentSoft : palette.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? palette.accent.opacity(0.55) : palette.line, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .black))
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

    private var hapticsView: some View {
        sectionCard {
            ForEach(Array(HapticLevel.allCases.enumerated()), id: \.element) { index, level in
                Button {
                    model.setHapticLevel(level)
                } label: {
                    HStack {
                        Text(level.label)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(palette.ink)
                        Spacer()
                        if model.hapticLevel == level {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(palette.accent)
                        }
                    }
                    .frame(height: 54)
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

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(palette.muted)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(palette.line, lineWidth: 1)
            )
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
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }

    private func settingsLink(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.ink)
                Spacer()
                Text(value)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.muted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.muted)
            }
            .frame(height: 56)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func settingsAction(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.ink)
                Spacer()
            }
            .frame(height: 54)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func submitLogin() {
        focusedField = nil
        Task { await model.login(username: username, password: password) }
    }
}

private struct SegmentPicker<Option: Hashable & Identifiable>: View where Option.ID == String {
    let options: [Option]
    let selection: Option
    let palette: AppPalette
    let label: (Option) -> String
    let onSelect: (Option) -> Void

    @Namespace private var namespace

    private var thumbFill: Color {
        palette.isDark ? Color.white.opacity(0.09) : palette.surface
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Button {
                    guard option != selection else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                        onSelect(option)
                    }
                } label: {
                    Text(label(option))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(option == selection ? palette.ink : palette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background {
                            if option == selection {
                                Capsule()
                                    .fill(thumbFill)
                                    .matchedGeometryEffect(id: "segment-thumb", in: namespace)
                                    .shadow(
                                        color: .black.opacity(palette.isDark ? 0.24 : 0.08),
                                        radius: 4,
                                        y: 2
                                    )
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(option))
                .accessibilityValue(option == selection ? "已选择" : "")
            }
        }
        .padding(3)
        .background(Capsule().fill(palette.surface2))
        .overlay(Capsule().stroke(palette.line, lineWidth: 1))
        .frame(maxWidth: 196)
    }
}

struct DateOverlay: View {
    @Bindable var model: AppModel
    let palette: AppPalette
    @State private var date = Date()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(palette.isDark ? 0.48 : 0.24)
                    .ignoresSafeArea()
                    .background(.ultraThinMaterial)
                    .onTapGesture { model.dateSheetOpen = false }

                VStack(alignment: .leading, spacing: 0) {
                    Text("修改时间")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette.ink)
                        .padding(.bottom, 18)

                    DatePicker("日期", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .tint(palette.accent)
                        .font(.system(size: 16, weight: .medium))
                        .padding(.vertical, 8)

                    Rectangle().fill(palette.line).frame(height: 1)

                    DatePicker("时间", selection: $date, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .tint(palette.accent)
                        .font(.system(size: 16, weight: .medium))
                        .padding(.vertical, 8)

                    HStack(spacing: 10) {
                        Button {
                            model.dateSheetOpen = false
                        } label: {
                            Text("取消")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.ink2)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(palette.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))

                        Button {
                            model.confirmDate(date)
                        } label: {
                            Text("完成")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.accentInk)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(palette.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                    }
                    .padding(.top, 18)
                }
                .padding(18)
                .frame(maxWidth: min(360, proxy.size.width - 24))
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(palette.line, lineWidth: 1)
                )
                .shadow(color: palette.sheetShadow, radius: 30, y: 16)
            }
        }
        .onAppear { date = model.entryDate }
    }
}
