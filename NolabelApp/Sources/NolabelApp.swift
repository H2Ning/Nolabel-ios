import SwiftUI

@main
struct NolabelApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(model.preferredColorScheme)
                .tint(model.themeMode == .light ? AppPalette.light.accent : AppPalette.dark.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: AppPalette {
        .palette(colorScheme).withNumberColors(model.numberFormat.colorScheme)
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.settingsPath) {
            rootContent
                .navigationDestination(for: SettingsSubview.self) { sub in
                    SettingsPage(sub: sub, model: model, palette: palette)
                }
        }
    }

    private var rootContent: some View {
        ZStack {
            palette.pageBG.ignoresSafeArea()
            appAtmosphere
                .ignoresSafeArea()
                .allowsHitTesting(false)

            BillsView(model: model, palette: palette)
                .allowsHitTesting(!model.settingsOpen && model.pendingDeleteBill == nil)

            if let title = model.undoDeleteTitle {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Text("已删除「\(title)」")
                            .scalableFont(14, weight: .medium)
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        Button {
                            Task { await model.undoDelete() }
                        } label: {
                            Text("撤销")
                                .scalableFont(15, weight: .semibold)
                                .foregroundStyle(palette.accentText)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: AppRadius.toast, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.toast, style: .continuous)
                            .stroke(palette.line, lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 92)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(7)
            }
        }
        .alert(
            "删除这笔账单？",
            isPresented: Binding(
                get: { model.pendingDeleteBill != nil },
                set: { _ in }
            )
        ) {
            Button("删除", role: .destructive) { model.confirmDeletePrompt() }
            Button("取消", role: .cancel) { model.cancelDeletePrompt() }
        } message: {
            Text(model.pendingDeleteBill.map { "\($0.title) · \($0.signedAmountText)" } ?? "")
        }
        .animation(reduceMotion ? nil : AppMotion.spring, value: model.settingsOpen)
        .animation(reduceMotion ? nil : AppMotion.spring, value: model.cashPlazaOpen)
        .animation(reduceMotion ? nil : AppMotion.spring, value: model.pendingDeleteBill?.id)
        .animation(reduceMotion ? nil : AppMotion.spring, value: model.undoDeleteTitle)
        .task {
            AlternateIconAlert.install()
            Haptics.prepare()
            AppShortcutRouter.handler = { shortcut in
                switch shortcut {
                case .newEntry:
                    model.openBillID = nil
                    model.openEntry()
                case .analysis:
                    model.openBillID = nil
                    model.cashPlazaOpen = true
                }
            }
            if let pending = AppShortcutRouter.pending {
                AppShortcutRouter.pending = nil
                AppShortcutRouter.handler?(pending)
            }
            CSVOpenRouter.handler = { url in
                Task { @MainActor in
                    model.receiveExternalCSVFile(url)
                }
            }
            if let pending = CSVOpenRouter.pending {
                CSVOpenRouter.pending = nil
                CSVOpenRouter.handler?(pending)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { model.entryOpen },
                set: { if !$0 { model.closeEntry() } }
            )
        ) {
            EntryView(model: model, palette: palette)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(
            isPresented: Binding(
                get: { model.cashPlazaOpen },
                set: { if !$0 { model.cashPlazaOpen = false } }
            )
        ) {
            CashPlazaView(
                model: model,
                palette: palette,
                detent: Binding(
                    get: { model.plazaDetent },
                    set: { model.plazaDetent = $0 }
                ),
                onClose: {
                    Haptics.lower()
                    model.cashPlazaOpen = false
                }
            )
        }
    }

    private var appAtmosphere: some View {
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
}
