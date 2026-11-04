import SwiftUI
import UIKit

struct CashStageView: View {
    let cents: Int
    let palette: AppPalette
    @Binding var yaw: Double
    @Binding var pitch: Double
    @Binding var mode: Int

    @State private var dragOrigin: (yaw: Double, pitch: Double)?

    private var groups: [CashGroup] {
        CashBreakdown.groups(for: cents)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                stageBackground
                grid

                if !groups.isEmpty {
                    if mode == 3 {
                        CashNoteGrid(cents: cents, palette: palette)
                            .transition(.opacity)
                    } else {
                        CashScene3DView(
                            cents: cents,
                            mode: mode,
                            yaw: yaw,
                            pitch: pitch,
                            isDark: palette.isDark
                        )
                        .transition(.opacity)
                    }
                }

                if !groups.isEmpty {
                    modeBadge
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(11)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(palette.line, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .gesture(rotationGesture, including: mode == 3 || groups.isEmpty ? .none : .all)
            .simultaneousGesture(
                TapGesture().onEnded {
                    if !groups.isEmpty { cycleMode() }
                }
            )
            .animation(.easeOut(duration: 0.18), value: mode)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("轻点切换现金摆放方式")
        }
    }

    private var stageBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        palette.stage,
                        palette.isDark ? Color(hex: 0x0B1510) : Color(hex: 0xDCE7DF)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [palette.isDark ? Color.white.opacity(0.035) : Color.white.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 90)
            }
    }

    private var grid: some View {
        Canvas { context, size in
            let step: CGFloat = 34
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(palette.stageGrid), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
    }

    private var modeBadge: some View {
        HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { value in
                Circle()
                    .fill(value == mode ? palette.ink2 : palette.muted.opacity(0.35))
                    .frame(width: value == mode ? 5 : 4, height: value == mode ? 5 : 4)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(palette.isDark ? Color.black.opacity(0.18) : Color.white.opacity(0.36), in: Capsule())
    }

    private var rotationGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = (yaw, pitch)
                }
                guard let origin = dragOrigin else { return }
                yaw = max(-80, min(80, origin.yaw - Double(value.translation.width) * 0.55))
                pitch = max(26, min(66, origin.pitch - Double(value.translation.height) * 0.30))
            }
            .onEnded { _ in
                dragOrigin = nil
                withAnimation(AppMotion.spring) {
                    yaw = max(-80, min(80, yaw))
                    pitch = max(26, min(66, pitch))
                }
            }
    }

    private func cycleMode() {
        withAnimation(AppMotion.quick) {
            mode = mode % 3 + 1
        }
        Haptics.pick()
    }

    private var accessibilityLabel: String {
        guard !groups.isEmpty else { return "金额为零，未生成现钞" }
        let total = CashBreakdown.totalNotes(groups)
        let pieces = groups.map { "\($0.denomination.name) \($0.count) 张" }.joined(separator: "，")
        let modeText: String
        switch mode {
        case 2: modeText = "按面额分组"
        case 3: modeText = "全部展开"
        default: modeText = "整叠摆放"
        }
        return "共 \(total) 张：\(pieces)。当前\(modeText)。左右拖动可旋转，轻点切换摆放方式。"
    }
}

private struct CashNoteGrid: View {
    let cents: Int
    let palette: AppPalette

    private var notes: [Denomination] {
        let groups = CashBreakdown.groups(for: cents)
        var result: [Denomination] = []
        for group in groups {
            result.append(contentsOf: Array(repeating: group.denomination, count: group.count))
        }
        return result
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 5),
                spacing: 5
            ) {
                ForEach(Array(notes.enumerated()), id: \.offset) { _, denom in
                    NoteThumbnail(denom: denom)
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct NoteThumbnail: View {
    let denom: Denomination

    var body: some View {
        Group {
            if let image = NoteAsset.image(denom.imageName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
            }
        }
        .aspectRatio(denom.ratio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(Color.black.opacity(0.20), lineWidth: 0.5)
        )
    }
}

private enum NoteAsset {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) {
            return cached
        }
        guard let path = Bundle.main.path(forResource: name, ofType: "jpg", inDirectory: "Notes"),
              let image = UIImage(contentsOfFile: path) else {
            return nil
        }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}
