import SwiftUI

struct BillsView: View {
    @Bindable var model: AppModel
    let palette: AppPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var monthShiftDirection = 1

    init(model: AppModel, palette: AppPalette) {
        self._model = Bindable(model)
        self.palette = palette
    }

    var body: some View {
        let _ = model.numberFormat
        ScrollView {
            VStack(spacing: 0) {
                monthMeta
                summaryCard
                listSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 128)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .bottomLeading) {
            addButton
                .padding(.leading, 20)
                .padding(.bottom, 22)
        }
        .overlay(alignment: .bottom) {
            if model.writing {
                ProgressView()
                    .tint(palette.ink)
                    .padding(10)
                    .glassCircle(interactive: false)
                    .padding(.bottom, 28)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { model.openBillID = nil; model.openSettings() }) {
                    Image(systemName: "person")
                        .scalableFont(17, weight: .medium)
                        .foregroundStyle(palette.ink2)
                }
                .accessibilityLabel("设置")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: { shiftMonth(-1) }) {
                    Image(systemName: "chevron.left")
                        .scalableFont(16, weight: .medium)
                        .foregroundStyle(palette.ink2)
                }
                .accessibilityLabel("上个月")

                Button(action: { shiftMonth(1) }) {
                    Image(systemName: "chevron.right")
                        .scalableFont(16, weight: .medium)
                        .foregroundStyle(palette.ink2)
                }
                .accessibilityLabel("下个月")
            }
        }
        .navigationTitle("账单")
        .navigationBarTitleDisplayMode(.large)
    }

    /// The system large title owns the page title; the content keeps only the
    /// month context line, which the bar cannot express as a subtitle.
    private var monthMeta: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.monthTitle)
                .scalableFont(13, weight: .medium)
                .tracking(0.6)
                .foregroundStyle(palette.muted)
                .contentTransition(.numericText())
            Spacer()
            Text("\(model.monthBills.count) 笔")
                .scalableFont(13, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(palette.muted)
                .contentTransition(.numericText())
        }
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    private func shiftMonth(_ direction: Int) {
        model.openBillID = nil
        monthShiftDirection = direction
        withAnimation(reduceMotion ? nil : AppMotion.spring) {
            model.shiftMonth(direction)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("该月支出")
                    .scalableFont(13, weight: .medium)
                    .tracking(0.2)
                    .foregroundStyle(palette.muted)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .scalableFont(8, weight: .bold)
                        .foregroundStyle(palette.faint)
                    Text(model.monthPeriod)
                        .scalableFont(12, weight: .medium)
                        .foregroundStyle(palette.muted)
                        .contentTransition(.numericText())
                    Image(systemName: "chevron.right")
                        .scalableFont(8, weight: .bold)
                        .foregroundStyle(palette.faint)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Formats.currencySymbol)")
                    .scalableFont(20, weight: .semibold, design: .rounded)
                    .foregroundStyle(palette.accent)
                Text(Formats.money(model.monthExpense))
                    .scalableFont(43, weight: .bold, design: .rounded)
                    .tracking(-1.3)
                    .monospacedDigit()
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .contentTransition(.numericText())
            }
            .padding(.top, 4)

            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
                .padding(.top, 12)

            HStack(spacing: 8) {
                Circle()
                    .fill(palette.income)
                    .frame(width: 6, height: 6)
                Text("收入")
                    .scalableFont(12, weight: .medium)
                    .foregroundStyle(palette.ink2)
                Text(Formats.money(model.monthIncome))
                    .scalableFont(12, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(palette.income)
                    .contentTransition(.numericText())
                Spacer()
                Text("\(model.monthBills.count) 笔 · \(model.monthNotes) 张现钞")
                    .scalableFont(12, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(palette.muted)
                    .contentTransition(.numericText())
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .onTapGesture {
            model.openBillID = nil
            Haptics.lift()
            withAnimation(reduceMotion ? nil : AppMotion.spring) {
                model.cashPlazaOpen = true
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let horizontal = value.translation.width
                    guard abs(horizontal) > abs(value.translation.height),
                          abs(horizontal) > 60 else { return }
                    withAnimation(reduceMotion ? nil : AppMotion.spring) {
                        model.shiftMonth(horizontal < 0 ? 1 : -1)
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("该月支出 \(Formats.money(model.monthExpense)) 元，收入 \(Formats.money(model.monthIncome)) 元，\(model.monthBills.count) 笔，\(model.monthNotes) 张现钞")
        .accessibilityHint("左右滑动切换月份，轻点打开月度分析")
    }

    private var monthListTransition: AnyTransition {
        let incoming: Edge = monthShiftDirection > 0 ? .trailing : .leading
        let outgoing: Edge = monthShiftDirection > 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: incoming).combined(with: .opacity),
            removal: .move(edge: outgoing).combined(with: .opacity)
        )
    }

    private var listSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("账单明细")
                    .scalableFont(16, weight: .semibold)
                    .foregroundStyle(palette.ink)
                Spacer()
                Button(action: { model.openBillID = nil; model.toggleSort() }) {
                    Text(model.sortDesc ? "按时间倒序" : "按时间正序")
                        .scalableFont(12, weight: .medium)
                        .foregroundStyle(palette.muted)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.96))
            }
            .padding(.top, 24)
            .padding(.bottom, 8)

            ZStack(alignment: .top) {
                if model.monthBills.isEmpty {
                    emptyState
                        .id("empty-\(model.selectedMonthKey)")
                        .transition(monthListTransition)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(model.monthGroups()) { group in
                            DayCapsuleView(model: model, group: group, palette: palette)
                        }
                    }
                    .id(model.selectedMonthKey)
                    .transition(monthListTransition)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: AppRadius.micro, style: .continuous)
                .fill(palette.surface)
                .frame(width: 76, height: 58)
                .overlay(
                    VStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(palette.line)
                                .frame(height: 1)
                        }
                    }
                    .padding(.horizontal, 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.micro, style: .continuous)
                        .stroke(palette.lineStrong, lineWidth: 1)
                )
                .rotationEffect(.degrees(-2))
                .padding(.bottom, 16)

            Text(model.bills.isEmpty ? "还没有账单" : "这个月还没有账单")
                .scalableFont(17, weight: .semibold)
                .foregroundStyle(palette.ink)

            Button(action: { model.openBillID = nil; model.openEntry() }) {
                Text("记一笔")
                    .scalableFont(14, weight: .semibold)
                    .foregroundStyle(palette.accentInk)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .glassCapsule(tint: palette.accent)
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.96))
            .padding(.top, 18)
        }
        .padding(.top, 38)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity)
    }

    private var addButton: some View {
        Button(action: { model.openBillID = nil; model.openEntry() }) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .scalableFont(17, weight: .semibold)
                Text("记一笔")
                    .scalableFont(16, weight: .semibold)
            }
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 19)
            .frame(minHeight: 52)
            .glassCapsule(tint: palette.accent.opacity(0.3), clear: true)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .accessibilityLabel("记一笔")
    }
}

struct DayCapsuleView: View {
    @Bindable var model: AppModel
    let group: DayGroup
    let palette: AppPalette

    private var netText: String {
        if group.net > 0 { return Formats.signedMoney(group.net, type: .income) }
        if group.net < 0 { return Formats.signedMoney(-group.net, type: .expense) }
        return "\(Formats.currencySymbol)0.00"
    }

    private var netColor: Color {
        if group.net > 0 { return palette.income }
        if group.net < 0 { return palette.expense }
        return palette.surface2
    }

    private var netTextColor: Color {
        guard group.net != 0 else { return palette.ink }
        let type: BillType = group.net > 0 ? .income : .expense
        return model.numberFormat.colorScheme.netTextColor(for: type, isDark: palette.isDark)
    }

    var body: some View {
        let _ = model.numberFormat
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(DateHelp.dayTitle(group.iso))
                    .scalableFont(13, weight: .semibold)
                    .foregroundStyle(palette.ink2)
                if group.isToday {
                    Text("今天")
                        .scalableFont(11, weight: .semibold)
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(palette.accentSoft, in: Capsule())
                }
                Rectangle()
                    .fill(palette.line)
                    .frame(height: 1)
                Text(netText)
                    .scalableFont(16, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(netTextColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(netColor, in: Capsule())
                    .accessibilityLabel("当日支出 \(Formats.money(group.expense)) 元，收入 \(Formats.money(group.income)) 元")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 9)
            .background(palette.surface2.opacity(palette.isDark ? 0.55 : 0.62))

            LazyVStack(spacing: 0) {
                ForEach(Array(group.bills.enumerated()), id: \.element.id) { index, bill in
                    SwipeBillRow(
                        model: model,
                        bill: bill,
                        palette: palette,
                        showDivider: index < group.bills.count - 1
                    )
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
}

struct SwipeBillRow: View {
    @Bindable var model: AppModel
    let bill: Bill
    let palette: AppPalette
    let showDivider: Bool

    @State private var dragOffset: CGFloat = 0
    @State private var startOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var crossedReveal = false
    @State private var suppressTap = false
    @State private var isTouching = false

    private let reveal: CGFloat = 68
    private let circleSize: CGFloat = 44

    private var isOpen: Bool { model.openBillID == bill.id }
    private var offset: CGFloat {
        if isDragging { return dragOffset }
        return isOpen ? reveal : 0
    }

    private var appearProgress: CGFloat {
        max(0, min(1, (offset - 34) / 34))
    }

    private var deleteBrightness: Double {
        if palette.isDark {
            return -0.5 + 0.5 * appearProgress
        }
        return 0.5 - 0.5 * appearProgress
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                model.requestDelete(bill)
            } label: {
                Image(systemName: "trash")
                    .scalableFont(17, weight: .medium)
                    .foregroundStyle(.white)
                    .frame(width: circleSize, height: circleSize)
                    .background(palette.danger, in: Circle())
                    .brightness(deleteBrightness)
                    .scaleEffect(appearProgress)
                    .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.93))
            .frame(width: circleSize, height: circleSize)
            .padding(.trailing, 12)
            .allowsHitTesting(isOpen && !isDragging)
            .accessibilityLabel("删除 \(bill.title) \(Formats.money(bill.cents)) 元")

            HStack(spacing: 10) {
                Circle()
                    .fill(bill.type == .expense ? palette.expense : palette.income)
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(bill.title)
                        .scalableFont(16, weight: .semibold)
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(metaText)
                        .scalableFont(12, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(bill.signedAmountText)
                    .scalableFont(16, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(bill.type == .expense ? palette.expense : palette.income)
                    .lineLimit(1)
            }
            .padding(.leading, 16)
            .padding(.trailing, 26)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(isTouching && !isDragging ? palette.surface2 : palette.surface)
            .animation(.easeOut(duration: 0.06), value: isTouching)
            .overlay {
                if model.lastSavedBillID == bill.id {
                    Rectangle()
                        .fill(palette.accent.opacity(palette.isDark ? 0.14 : 0.10))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .overlay {
                HorizontalSwipeArea(
                    onTouchDown: { isTouching = true },
                    onTouchUp: { isTouching = false },
                    onBegan: {
                        isTouching = false
                        beginSwipe()
                    },
                    onChanged: updateSwipe,
                    onEnded: endSwipe,
                    onTap: handleRowTap
                )
                .accessibilityHidden(true)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                guard !suppressTap else { return }
                if isOpen {
                    withAnimation(AppMotion.spring) { model.openBillID = nil }
                } else {
                    model.openEntry(bill)
                }
            }
            .offset(x: -offset)
            .animation(AppMotion.grace, value: model.lastSavedBillID)

            if showDivider {
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(palette.line)
                        .frame(height: 1)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .animation(isDragging ? nil : AppMotion.spring, value: offset)
        .animation(isDragging ? nil : AppMotion.spring, value: isOpen)
        .accessibilityElement(children: .contain)
    }

    private var metaText: String {
        var parts: [String] = []
        if !bill.time.isEmpty { parts.append(bill.time) }
        if bill.count > 0 { parts.append("\(bill.count) 张") }
        if bill.kinds > 0 { parts.append("\(bill.kinds) 种面额") }
        return parts.joined(separator: " · ")
    }

    private func handleRowTap() {
        guard !suppressTap else { return }
        if isOpen || model.openBillID != nil {
            // The first tap while a delete action is revealed only dismisses it.
            Haptics.swipeClose()
            withAnimation(AppMotion.spring) { model.openBillID = nil }
            return
        }
        model.openEntry(bill)
    }

    private func beginSwipe() {
        guard !isDragging else { return }
        isTouching = false
        if model.openBillID != bill.id {
            model.openBillID = nil
        }
        isDragging = true
        crossedReveal = false
        startOffset = isOpen ? reveal : 0
        suppressTap = true
    }

    private func updateSwipe(_ translation: CGFloat) {
        guard isDragging else { return }
        let next = startOffset - translation
        if startOffset == 0 && next >= 34 && !crossedReveal {
            crossedReveal = true
            Haptics.detent()
        }
        dragOffset = min(reveal, max(0, next))
    }

    private func endSwipe(_ translation: CGFloat, _ predictedTranslation: CGFloat) {
        guard isDragging else { return }
        isDragging = false
        let projected = dragOffset + (-predictedTranslation) * 0.22
        let shouldOpen = projected > reveal * 0.42
        if shouldOpen != isOpen {
            if shouldOpen {
                Haptics.swipeOpen()
            } else {
                Haptics.swipeClose()
            }
        }
        withAnimation(AppMotion.spring) {
            model.openBillID = shouldOpen ? bill.id : nil
        }
        dragOffset = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            suppressTap = false
        }
    }


}
