import SwiftUI

@main
struct NolabelApp: App {
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
        ZStack {
            palette.pageBG.ignoresSafeArea()
            appAtmosphere
                .ignoresSafeArea()
                .allowsHitTesting(false)

            BillsView(model: model, palette: palette)
                .opacity(model.cashPlazaOpen ? 0.36 : 1)
                .scaleEffect(model.cashPlazaOpen ? 0.988 : 1)
                .allowsHitTesting(!model.settingsOpen && !model.cashPlazaOpen && model.pendingDeleteBill == nil)
                .animation(reduceMotion ? nil : AppMotion.spring, value: model.cashPlazaOpen)

            if model.settingsOpen {
                SettingsOverlay(model: model, palette: palette)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        )
                    )
                    .zIndex(3)
            }

            if model.dateSheetOpen && !model.entryOpen {
                DateOverlay(model: model, palette: palette)
                    .transition(.opacity)
                    .zIndex(4)
            }

            if model.cashPlazaOpen {
                CashPlazaView(
                    model: model,
                    palette: palette,
                    onClose: {
                        Haptics.lower()
                        model.cashPlazaOpen = false
                    }
                )
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    )
                )
                .zIndex(5)
            }

            if let bill = model.pendingDeleteBill {
                DeleteConfirmView(
                    bill: bill,
                    palette: palette,
                    onCancel: { model.cancelDeletePrompt() },
                    onConfirm: { suppressToday in
                        model.confirmDeletePrompt(suppressToday: suppressToday)
                    }
                )
                .zIndex(6)
            }
        }
        .animation(reduceMotion ? nil : AppMotion.spring, value: model.settingsOpen)
        .animation(reduceMotion ? nil : AppMotion.spring, value: model.cashPlazaOpen)
        .animation(reduceMotion ? nil : AppMotion.spring, value: model.pendingDeleteBill?.id)
        .task {
            Haptics.prepare()
            await model.bootstrap()
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { model.entryOpen },
                set: { if !$0 { model.closeEntry() } }
            )
        ) {
            EntryView(model: model, palette: palette)
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
