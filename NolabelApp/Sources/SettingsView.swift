import SwiftUI
import UniformTypeIdentifiers

struct SettingsOverlay: View {
    @Bindable var model: AppModel
    let palette: AppPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var username = ""
    @State private var password = ""
    @State private var showImporter = false
    @State private var showExporter = false
    @FocusState private var focusedField: Field?

    private enum Field { case username, password }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(palette.isDark ? 0.52 : 0.28)
                    .ignoresSafeArea()
                    .background(.ultraThinMaterial)
                    .onTapGesture { model.closeSettings() }

                ScrollView {
                    VStack(spacing: 0) {
                        header
                        if model.settingsSubview == .main {
                            mainView
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        } else {
                            appearanceView
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: min(390, proxy.size.width - 24))
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(palette.line, lineWidth: 1)
                    )
                    .shadow(color: palette.sheetShadow, radius: 34, y: 18)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: min(390, proxy.size.width - 24))
                .frame(maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 12)
            }
        }
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
            }
        }
    }

    private var header: some View {
        ZStack {
            HStack {
                if model.settingsSubview == .appearance {
                    Button {
                        withAnimation(AppMotion.spring) { model.settingsSubview = .main }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.ink2)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.92))
                    .glassCircle()
                    .accessibilityLabel("返回设置")
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
                Spacer()
                Button(action: { model.closeSettings() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.ink2)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle(scale: 0.92))
                .glassCircle()
                .accessibilityLabel("关闭设置")
            }
            Text(model.settingsSubview == .main ? "设置" : "外观")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(palette.ink)
        }
        .padding(.bottom, 20)
    }

    private var mainView: some View {
        VStack(spacing: 12) {
            accountCard
            sectionCard {
                settingsLink(title: "外观", value: model.themeMode.label) {
                    withAnimation(AppMotion.spring) { model.settingsSubview = .appearance }
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
                Text(model.authMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.expense)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.ink)
                        Text("诺诺账号")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.muted)
                    }
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
                        .foregroundStyle(palette.expense)
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
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
