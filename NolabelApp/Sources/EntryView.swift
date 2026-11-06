import SwiftUI

struct EntryView: View {
    @Bindable var model: AppModel
    let palette: AppPalette
    @FocusState private var noteFocused: Bool

    private let keySpacing: CGFloat = 8
    @State private var backspaceRepeatTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    palette.pageBG.ignoresSafeArea()

                    VStack(spacing: 0) {
                    CashStageView(
                        source: .cents(model.entryPreviewCents),
                        palette: palette,
                        yaw: $model.cashYaw,
                        pitch: $model.cashPitch,
                        mode: model.cashMode,
                        onSelectMode: { model.setCashMode($0) },
                        onReady: {}
                    )
                    .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 360)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .layoutPriority(0)

                    // Fixed gap: the stage gives up height first.
                    Color.clear.frame(height: 12)

                    entryCard
                        .padding(.horizontal, 20)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(2)

                    if noteFocused {
                        // Same gap the keypad used, so the card keeps its place.
                        Color.clear.frame(height: 12)
                    } else {
                        keypad
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, max(8, proxy.safeAreaInsets.bottom))
                            .layoutPriority(2)
                            .transition(.opacity)
                    }
                    }
                }
            }
            .onTapGesture {
                noteFocused = false
            }
            .animation(.easeOut(duration: 0.18), value: noteFocused)
            .onDisappear { stopBackspaceRepeat() }
            .sheet(
                isPresented: Binding(
                    get: { model.dateSheetOpen },
                    set: { if !$0 { model.dateSheetOpen = false } }
                )
            ) {
                DatePickerSheet(model: model, palette: palette)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { model.closeEntry() }) {
                        Image(systemName: "xmark")
                            .scalableFont(15, weight: .semibold)
                            .foregroundStyle(palette.ink2)
                    }
                    .accessibilityLabel("取消并返回账单")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func startBackspaceRepeat() {
        guard backspaceRepeatTask == nil else { return }
        Haptics.detent()
        backspaceRepeatTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            while !Task.isCancelled {
                model.pressBackspace()
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
        }
    }

    private func stopBackspaceRepeat() {
        backspaceRepeatTask?.cancel()
        backspaceRepeatTask = nil
    }

    private var entryCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Formats.currencySymbol)")
                        .scalableFont(20, weight: .semibold, design: .rounded)
                        .foregroundStyle(palette.accent)
                    Text(model.entryDisplay)
                        .scalableFont(38, weight: .bold, design: .rounded)
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
                    .scalableFont(13, weight: .medium)
                    .foregroundStyle(palette.muted)
                TextField("备注", text: $model.entryNote)
                    .scalableFont(15, weight: .medium)
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
                    withAnimation(AppMotion.spring) { model.dateSheetOpen = true }
                    Haptics.soft()
                } label: {
                    Text(DateHelp.dayTitle(DateHelp.iso(from: model.entryDate)) + " · \(DateHelp.time(from: model.entryDate))")
                        .scalableFont(12, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.96))
                .accessibilityLabel("修改日期和时间")
            }
            .padding(.top, 12)
            .padding(.bottom, 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 10)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
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
                    .scalableFont(12, weight: .semibold)
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
                    .scalableFont(12, weight: .medium)
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
                .scalableFont(20, weight: .medium)
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
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
                .scalableFont(19, weight: .medium)
                .foregroundStyle(palette.ink2)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(palette.line, lineWidth: 1)
                )
        }
        .buttonStyle(HapticKeyStyle(weight: .light, intensity: 0.82, level: model.hapticLevel))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in startBackspaceRepeat() }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in stopBackspaceRepeat() }
        )
        .accessibilityLabel("退格，长按连续删除")
    }

    private var operatorKey: some View {
        Button {
            model.cycleOperator()
        } label: {
            HStack(spacing: 2) {
                ForEach(EntryOperator.allCases, id: \.rawValue) { op in
                    Text(op.rawValue)
                        .scalableFont(14, weight: .semibold)
                        .foregroundStyle(model.entryOperator == op ? palette.accent : palette.ink2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(palette.surface2, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
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
                .scalableFont(21, weight: .semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(palette.success, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        }
        .buttonStyle(HapticKeyStyle(weight: .medium, intensity: 0.76, level: model.hapticLevel))
    }

    private var saveKey: some View {
        Button {
            Task { await model.saveEntry() }
        } label: {
            Text(model.writing ? "保存中" : "保存")
                .scalableFont(16, weight: .semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(palette.primaryAction, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .opacity(model.entryPreviewCents > 0 ? 1 : 0.55)
        }
        .buttonStyle(HapticKeyStyle(weight: .medium, intensity: 0.86, level: model.hapticLevel))
        .disabled(model.entryPreviewCents <= 0 || model.writing)
        .accessibilityLabel("保存这笔账")
    }
}


struct DatePickerSheet: View {
    @Bindable var model: AppModel
    let palette: AppPalette
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(palette.accent)
                        .labelsHidden()

                    DatePicker("时间", selection: $date, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxHeight: 160)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .background(palette.pageBG.ignoresSafeArea())
            .navigationTitle("修改时间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        Haptics.soft()
                        model.dateSheetOpen = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        Haptics.complete()
                        model.confirmDate(date)
                    }
                }
            }
        }
        .onAppear { date = model.entryDate }
    }
}
