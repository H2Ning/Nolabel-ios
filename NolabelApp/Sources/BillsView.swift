import SwiftUI

struct BillsView: View {
    @Bindable var model: AppModel
    let palette: AppPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rowInset = EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)

    init(model: AppModel, palette: AppPalette) {
        self._model = Bindable(model)
        self.palette = palette
    }

    var body: some View {
        let _ = model.numberFormat
        VStack(spacing: 0) {
            topBar
            List {
                Section {
                    heading
                        .listRowInsets(rowInset)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    summaryCard
                        .listRowInsets(rowInset)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    listHeader
                        .listRowInsets(rowInset)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if model.monthBills.isEmpty {
                    emptyState
                        .listRowInsets(rowInset)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(model.monthGroups()) { group in
                        Section {
                            DayHeaderRow(
                                group: group,
                                model: model,
                                palette: palette
                            )
                            .listRowInsets(rowInset)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .accessibilityAddTraits(.isHeader)

                            ForEach(Array(group.bills.enumerated()), id: \.element.id) { index, bill in
                                BillRow(
                                    model: model,
                                    bill: bill,
                                    palette: palette,
                                    showDivider: index < group.bills.count - 1,
                                    isLast: index == group.bills.count - 1
                                )
                                .listRowInsets(rowInset)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        model.requestDelete(bill)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .tint(palette.danger)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .listSectionSpacing(12)
            .contentMargins(.top, 0, for: .scrollContent)
            .contentMargins(.bottom, 120, for: .scrollContent)
        }
        .overlay(alignment: .bottomTrailing) {
            addButton
                .padding(.trailing, 20)
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
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: { model.openSettings() }) {
                Image(systemName: "person")
                    .scalableFont(17, weight: .medium)
                    .foregroundStyle(palette.ink2)
                    .frame(width: 46, height: 46)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.94))
            .glassCircle()
            .accessibilityLabel("设置")

            Spacer(minLength: 0)

            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 0) {
                    monthButton(systemName: "chevron.left", label: "上个月") {
                        withAnimation(reduceMotion ? nil : AppMotion.spring) {
                            model.shiftMonth(-1)
                        }
                    }
                    Rectangle()
                        .fill(palette.line)
                        .frame(width: 1, height: 22)
                    monthButton(systemName: "chevron.right", label: "下个月") {
                        withAnimation(reduceMotion ? nil : AppMotion.spring) {
                            model.shiftMonth(1)
                        }
                    }
                }
                .frame(height: 46)
                .glassEffect(.regular, in: .capsule)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func monthButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .scalableFont(16, weight: .medium)
                .foregroundStyle(palette.ink2)
                .frame(width: 46, height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel(label)
    }

    private var heading: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.monthTitle)
                    .scalableFont(12, weight: .medium)
                    .tracking(1.1)
                    .foregroundStyle(palette.muted)
                    .contentTransition(.numericText())
                Text("账单")
                    .scalableFont(36, weight: .bold)
                    .tracking(-0.8)
                    .foregroundStyle(palette.ink)
            }
            Spacer()
            Text("\(model.monthBills.count) 笔")
                .scalableFont(13, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(palette.muted)
                .contentTransition(.numericText())
                .padding(.bottom, 4)
        }
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("该月支出")
                    .scalableFont(13, weight: .medium)
                    .tracking(0.2)
                    .foregroundStyle(palette.muted)
                Spacer()
                Text(model.monthPeriod)
                    .scalableFont(12, weight: .medium)
                    .foregroundStyle(palette.muted)
                    .contentTransition(.numericText())
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥")
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
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            Haptics.lift()
            withAnimation(reduceMotion ? nil : AppMotion.spring) {
                model.cashPlazaOpen = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("该月支出 \(Formats.money(model.monthExpense)) 元，收入 \(Formats.money(model.monthIncome)) 元，\(model.monthBills.count) 笔，\(model.monthNotes) 张现钞")
    }

    private var listHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("账单明细")
                .scalableFont(16, weight: .semibold)
                .foregroundStyle(palette.ink)
            Spacer()
            Button(action: { model.toggleSort() }) {
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
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
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
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.lineStrong, lineWidth: 1)
                )
                .rotationEffect(.degrees(-2))
                .padding(.bottom, 16)

            Text(model.bills.isEmpty ? "还没有账单" : "这个月还没有账单")
                .scalableFont(17, weight: .semibold)
                .foregroundStyle(palette.ink)

            Button(action: { model.openEntry() }) {
                Text("记一笔")
                    .scalableFont(14, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(palette.surface, in: Capsule())
                    .overlay(Capsule().stroke(palette.line, lineWidth: 1))
            }
            .buttonStyle(PressableStyle(scale: 0.96))
            .padding(.top, 18)
        }
        .padding(.top, 38)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity)
    }

    private var addButton: some View {
        Button(action: { model.openEntry() }) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .scalableFont(17, weight: .semibold)
                Text("记一笔")
                    .scalableFont(16, weight: .semibold)
            }
            .foregroundStyle(palette.accentInk)
            .padding(.horizontal, 19)
            .frame(minHeight: 52)
            .glassCapsule(tint: palette.accent)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .accessibilityLabel("记一笔")
    }
}

private struct DayHeaderRow: View {
    let group: DayGroup
    let model: AppModel
    let palette: AppPalette

    private var netText: String {
        if group.net > 0 { return Formats.signedMoney(group.net, type: .income) }
        if group.net < 0 { return Formats.signedMoney(-group.net, type: .expense) }
        return "¥0.00"
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
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 26,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 26,
                style: .continuous
            )
            .fill(palette.surface2.opacity(palette.isDark ? 0.55 : 0.62))
        )
    }
}

private struct BillRow: View {
    @Bindable var model: AppModel
    let bill: Bill
    let palette: AppPalette
    let showDivider: Bool
    let isLast: Bool

    var body: some View {
        Button {
            model.openEntry(bill)
        } label: {
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
            .padding(.trailing, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: isLast ? 26 : 0,
                    bottomTrailingRadius: isLast ? 26 : 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(palette.surface)
            )
            .overlay(alignment: .bottom) {
                if showDivider {
                    Rectangle()
                        .fill(palette.line)
                        .frame(height: 1)
                        .padding(.leading, 16)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if model.lastSavedBillID == bill.id {
                    Rectangle()
                        .fill(palette.accent.opacity(palette.isDark ? 0.14 : 0.10))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BillRowButtonStyle(palette: palette))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bill.title)，\(bill.signedAmountText)，\(bill.time)")
        .accessibilityHint("轻点编辑这笔账单")
    }

    private var metaText: String {
        var parts: [String] = []
        if !bill.time.isEmpty { parts.append(bill.time) }
        if bill.count > 0 { parts.append("\(bill.count) 张") }
        if bill.kinds > 0 { parts.append("\(bill.kinds) 种面额") }
        return parts.joined(separator: " · ")
    }
}

private struct BillRowButtonStyle: ButtonStyle {
    let palette: AppPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? palette.surface2 : Color.clear)
    }
}
