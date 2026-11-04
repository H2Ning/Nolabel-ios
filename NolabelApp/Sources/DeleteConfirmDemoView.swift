import SwiftUI

/// Preview-only design. The production delete path is intentionally not wired
/// until the user approves this confirmation pattern.
struct DeleteConfirmDemoView: View {
    let bill: Bill
    let palette: AppPalette
    let onCancel: () -> Void

    @State private var suppressToday = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(palette.isDark ? 0.56 : 0.26)
                    .ignoresSafeArea()
                    .background(.ultraThinMaterial)
                    .onTapGesture { onCancel() }

                VStack(alignment: .leading, spacing: 0) {
                    Text("删除这笔账单？")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(palette.ink)
                        .padding(.top, 2)

                    HStack(spacing: 10) {
                        Circle()
                            .fill(bill.type == .expense ? palette.expense : palette.income)
                            .frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bill.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(palette.ink)
                                .lineLimit(1)
                            Text(bill.time.isEmpty
                                 ? DateHelp.dayTitle(bill.iso)
                                 : "\(DateHelp.dayTitle(bill.iso)) · \(bill.time)")
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(palette.muted)
                        }
                        Spacer(minLength: 8)
                        Text(bill.signedAmountText)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(bill.type == .expense ? palette.expense : palette.income)
                    }
                    .padding(13)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(palette.line, lineWidth: 1)
                    )
                    .padding(.top, 16)

                    Button {
                        suppressToday.toggle()
                        Haptics.pick()
                    } label: {
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(suppressToday ? palette.accent : Color.clear)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(suppressToday ? Color.clear : palette.line, lineWidth: 1.3)
                                )
                                .overlay {
                                    if suppressToday {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(palette.accentInk)
                                    }
                                }
                            Text("今天之内不再提示")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(palette.ink2)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .frame(height: 40)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    .padding(.bottom, 16)

                    HStack(spacing: 10) {
                        Button(action: onCancel) {
                            Text("取消")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.ink2)
                                .frame(maxWidth: .infinity)
                                .frame(height: 47)
                                .background(palette.surface2, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))

                        Button(action: onCancel) {
                            Text("删除")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 47)
                                .background(palette.expense, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                    }
                }
                .padding(20)
                .frame(maxWidth: min(360, proxy.size.width - 40))
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(palette.line, lineWidth: 1)
                )
                .shadow(color: palette.sheetShadow, radius: 34, y: 18)
            }
        }
        .transition(.opacity)
    }
}
