import SwiftUI

struct EntryView: View {
    @Bindable var model: AppModel
    let palette: AppPalette
    @FocusState private var noteFocused: Bool
    @State private var dateLabelFrame: CGRect = .zero

    private let keySpacing: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let stageHeight = max(184, min(360, proxy.size.height - 382))
            ZStack(alignment: .top) {
                palette.pageBG.ignoresSafeArea()

                VStack(spacing: 0) {
                HStack {
                    Button(action: { model.closeEntry() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.ink2)
                            .frame(width: 46, height: 46)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.92))
                    .glassCircle()
                    .accessibilityLabel("取消并返回账单")
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)

                CashStageView(
                    source: .cents(model.entryPreviewCents),
                    palette: palette,
                    yaw: $model.cashYaw,
                    pitch: $model.cashPitch,
                    mode: model.cashMode,
                    onCycle: { model.cycleCashMode() },
                    onReady: {}
                )
                .frame(height: stageHeight)
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer(minLength: 12)

                entryCard
                    .padding(.horizontal, 20)
                    .layoutPriority(1)

                keypad
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, max(8, proxy.safeAreaInsets.bottom))
                    .layoutPriority(1)
                }
            }
        }
        .onTapGesture {
            noteFocused = false
        }
        .onPreferenceChange(DateLabelFrameKey.self) { dateLabelFrame = $0 }
        .overlay {
            if model.dateSheetOpen {
                DateOverlay(
                    model: model,
                    palette: palette,
                    genieTarget: dateLabelFrame == .zero
                        ? nil
                        : CGPoint(x: dateLabelFrame.midX, y: dateLabelFrame.midY)
                )
                .transition(.opacity)
            }
        }
    }

    private var entryCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("¥")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.accent)
                    Text(model.entryDisplay)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .tracking(-1.2)
                        .monospacedDigit()
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: 2, height: 24)
                        .padding(.leading, 2)
                        .opacity(0.9)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 4)
                typeSwitch
            }

            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
                .padding(.top, 12)

            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.muted)
                TextField("备注", text: $model.entryNote)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .focused($noteFocused)
                    .submitLabel(.done)
                    .onSubmit { noteFocused = false }
                    .onChange(of: model.entryNote) { _, newValue in
                        if newValue.count > 24 {
                            model.entryNote = String(newValue.prefix(24))
                        }
                    }
                Spacer(minLength: 8)
                Button {
                    noteFocused = false
                    model.dateSheetOpen = true
                    Haptics.soft()
                } label: {
                    Text(DateHelp.dayTitle(DateHelp.iso(from: model.entryDate)) + " · \(DateHelp.time(from: model.entryDate))")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }
                .buttonStyle(PressableStyle(scale: 0.96))
                .accessibilityLabel("修改日期和时间")
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: DateLabelFrameKey.self,
                            value: geo.frame(in: .global)
                        )
                    }
                )
            }
            .padding(.top, 12)
            .padding(.bottom, 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 10)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }

    private var typeSwitch: some View {
        HStack(spacing: 2) {
            segmentButton(.expense)
            segmentButton(.income)
        }
        .padding(3)
        .background(palette.surface2, in: Capsule())
    }

    private func segmentButton(_ type: BillType) -> some View {
        let selected = model.entryType == type
        return Button {
            withAnimation(AppMotion.quick) { model.changeType(type) }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(type == .expense ? palette.expense : palette.income)
                    .frame(width: 6, height: 6)
                Text(type == .expense ? "支出" : "收入")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(selected ? palette.ink : palette.muted)
            .padding(.horizontal, 9)
            .frame(height: 29)
            .background(
                selected ? palette.surface : Color.clear,
                in: Capsule()
            )
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var keypad: some View {
        VStack(spacing: 7) {
            if !model.entryError.isEmpty {
                Text(model.entryError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.danger)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 1)
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: keySpacing), count: 4),
                spacing: keySpacing
            ) {
                key("7") { model.pressDigit("7") }
                key("8") { model.pressDigit("8") }
                key("9") { model.pressDigit("9") }
                backspaceKey

                key("4") { model.pressDigit("4") }
                key("5") { model.pressDigit("5") }
                key("6") { model.pressDigit("6") }
                operatorKey

                key("1") { model.pressDigit("1") }
                key("2") { model.pressDigit("2") }
                key("3") { model.pressDigit("3") }
                equalsKey

                key(".") { model.pressDecimal() }
                key("0") { model.pressDigit("0") }
                key("00") { model.pressDoubleZero() }
                saveKey
            }
        }
    }

    private func key(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(palette.line, lineWidth: 1)
                )
        }
        .buttonStyle(HapticKeyStyle(weight: .light, intensity: 0.82, level: model.hapticLevel))
    }

    private var backspaceKey: some View {
        Button {
            model.pressBackspace()
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(palette.ink2)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(palette.line, lineWidth: 1)
                )
        }
        .buttonStyle(HapticKeyStyle(weight: .light, intensity: 0.82, level: model.hapticLevel))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.55).onEnded { _ in
                model.clearEntry()
                Haptics.warning()
            }
        )
        .accessibilityLabel("退格，长按清空")
    }

    private var operatorKey: some View {
        Button {
            model.cycleOperator()
        } label: {
            HStack(spacing: 2) {
                ForEach(EntryOperator.allCases, id: \.rawValue) { op in
                    Text(op.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(model.entryOperator == op ? palette.accent : palette.ink2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(palette.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.line, lineWidth: 1)
            )
        }
        .buttonStyle(HapticKeyStyle(weight: .medium, intensity: 0.68, level: model.hapticLevel))
        .accessibilityLabel("选择运算，快速连按切换")
        .accessibilityValue(model.entryOperator?.label ?? "未选择")
    }

    private var equalsKey: some View {
        Button {
            model.pressEquals()
        } label: {
            Text("=")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color(hex: 0x2E9F5B), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(HapticKeyStyle(weight: .medium, intensity: 0.76, level: model.hapticLevel))
    }

    private var saveKey: some View {
        Button {
            Task { await model.saveEntry() }
        } label: {
            Text(model.writing ? "保存中" : "保存")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color(hex: 0x3B7BE8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(model.entryPreviewCents > 0 ? 1 : 0.55)
        }
        .buttonStyle(HapticKeyStyle(weight: .medium, intensity: 0.86, level: model.hapticLevel))
        .disabled(model.entryPreviewCents <= 0 || model.writing)
        .accessibilityLabel("保存这笔账")
    }
}

private struct DateLabelFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
