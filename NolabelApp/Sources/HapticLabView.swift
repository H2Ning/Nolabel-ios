import SwiftfulHaptics
import SwiftUI

/// Temporary audition page for choosing the save and delete haptics.
/// Presets come from SwiftfulHaptics (MIT) plus Apple's system generators.
/// Remove this file, the settings row and the `hapticLab` case once a pick
/// is made.
struct HapticLabView: View {
    let palette: AppPalette
    @State private var manager = HapticManager()

    private struct Preset: Identifiable {
        let id: Int
        let title: String
        let detail: String
        let option: HapticOption
    }

    private var savePresets: [Preset] {
        [
            Preset(id: 1, title: "系统成功", detail: "Apple · 通知成功", option: .success),
            Preset(id: 2, title: "支付成功", detail: "SwiftfulHaptics · paymentSuccess", option: .paymentSuccess()),
            Preset(id: 3, title: "收据保存", detail: "SwiftfulHaptics · receiptSaved", option: .receiptSaved()),
            Preset(id: 4, title: "硬币落掌", detail: "SwiftfulHaptics · coinCollectSingle", option: .coinCollectSingle()),
            Preset(id: 5, title: "表单提交", detail: "SwiftfulHaptics · formSubmit", option: .formSubmit()),
            Preset(id: 6, title: "双击确认", detail: "SwiftfulHaptics · doubleTapLike", option: .doubleTapLike())
        ]
    }

    private var deletePresets: [Preset] {
        [
            Preset(id: 1, title: "系统警告", detail: "Apple · 通知警告", option: .warning),
            Preset(id: 2, title: "单次硬敲", detail: "Apple · UIImpactFeedbackGenerator(.rigid)", option: .rigid),
            Preset(id: 3, title: "滑动删除", detail: "SwiftfulHaptics · swipeAction(delete)", option: .swipeAction(actionType: "delete")),
            Preset(id: 4, title: "关闭回落", detail: "SwiftfulHaptics · modalDismiss", option: .modalDismiss()),
            Preset(id: 5, title: "通知弹出", detail: "SwiftfulHaptics · notificationPop", option: .notificationPop()),
            Preset(id: 6, title: "输入错误", detail: "SwiftfulHaptics · inputError", option: .inputError())
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("点按试听。选定后告诉我「保存 几」和「删除 几」，我会换掉正式触感并删除这个临时页面。试听不受触感档位限制。")
                .scalableFont(12, weight: .regular)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            section(title: "保存账单", presets: savePresets)
            section(title: "删除账单", presets: deletePresets)
        }
    }

    private func section(title: String, presets: [Preset]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .scalableFont(13, weight: .medium)
                .foregroundStyle(palette.muted)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(presets) { preset in
                    row(preset)
                    if preset.id != presets.last?.id {
                        Rectangle()
                            .fill(palette.line)
                            .frame(height: 1)
                            .padding(.leading, 52)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(palette.surface2.opacity(palette.isDark ? 0.56 : 0.60))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .stroke(palette.line, lineWidth: 1)
            )
        }
    }

    private func row(_ preset: Preset) -> some View {
        Button {
            manager.playHaptic(option: preset.option)
        } label: {
            HStack(spacing: 12) {
                Text("\(preset.id)")
                    .scalableFont(12, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(palette.accent)
                    .frame(width: 24, height: 24)
                    .background(palette.accentSoft, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title)
                        .scalableFont(15, weight: .medium)
                        .foregroundStyle(palette.ink)
                    Text(preset.detail)
                        .scalableFont(11, weight: .regular)
                        .foregroundStyle(palette.muted)
                }

                Spacer(minLength: 8)

                Image(systemName: "play.circle")
                    .scalableFont(20, weight: .regular)
                    .foregroundStyle(palette.accent)
            }
            .frame(minHeight: 56)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
