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

    private var palette: AppPalette { .palette(colorScheme) }

    var body: some View {
        ZStack {
            palette.pageBG.ignoresSafeArea()
            appAtmosphere
                .ignoresSafeArea()
                .allowsHitTesting(false)

            BillsView(model: model, palette: palette)
                .opacity(model.entryOpen ? 0.36 : 1)
                .scaleEffect(model.entryOpen ? 0.988 : 1)
                .allowsHitTesting(!model.entryOpen && !model.settingsOpen)
                .animation(reduceMotion ? nil : AppMotion.spring, value: model.entryOpen)

            if model.entryOpen {
                EntryView(model: model, palette: palette)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        )
                    )
                    .zIndex(2)
            }

            if model.settingsOpen {
                SettingsOverlay(model: model, palette: palette)
                    .transition(.opacity)
                    .zIndex(3)
            }

            if model.dateSheetOpen {
                DateOverlay(model: model, palette: palette)
                    .transition(.opacity)
                    .zIndex(4)
            }

            if model.deleteDemoOpen {
                DeleteConfirmDemoView(
                    bill: model.monthBills.first ?? SampleData.bills[0],
                    palette: palette,
                    onCancel: { model.deleteDemoOpen = false }
                )
                .zIndex(6)
            }

            if model.plazaDemoOpen {
                CashPlazaDemoView(
                    bills: CashPlazaDemoData.bills,
                    palette: palette,
                    onClose: { model.plazaDemoOpen = false }
                )
                .zIndex(6)
            }
        }
        .animation(reduceMotion ? nil : AppMotion.spring, value: model.settingsOpen)
        .animation(reduceMotion ? nil : AppMotion.spring, value: model.entryOpen)
        .task {
            Haptics.prepare()
            await model.bootstrap()
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
