import SwiftUI
import UIKit

struct CashStageView: View {
    let cents: Int
    let palette: AppPalette
    @Binding var yaw: Double
    @Binding var pitch: Double

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
                    notes(in: proxy.size)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(palette.line, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .gesture(rotationGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
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

    private func notes(in size: CGSize) -> some View {
        let columns = groups.count <= 2 ? groups.count : (groups.count <= 4 ? 2 : 3)
        let rows = max(1, Int(ceil(Double(groups.count) / Double(max(columns, 1)))))
        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 24
        let cellWidth = (size.width - horizontalPadding * 2) / CGFloat(max(columns, 1))
        let cellHeight = (size.height - verticalPadding * 2) / CGFloat(max(rows, 1))
        let noteWidth = min(158, cellWidth * 0.92)

        return ZStack {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                let column = index % max(columns, 1)
                let row = index / max(columns, 1)
                let x = horizontalPadding + cellWidth * (CGFloat(column) + 0.5)
                let y = verticalPadding + cellHeight * (CGFloat(row) + 0.5)
                CashStackView(
                    group: group,
                    width: noteWidth * scaleFor(group.denomination),
                    palette: palette,
                    yaw: yaw + Double(index % 2 == 0 ? -5 : 5),
                    pitch: pitch,
                    tilt: Double(index % 3) * 3 - 3
                )
                .position(x: x, y: y)
                .zIndex(Double(100 - index))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: cents)
    }

    private func scaleFor(_ denomination: Denomination) -> CGFloat {
        switch denomination.value {
        case 10_000, 5_000, 2_000: 1.0
        case 1_000, 500, 100: 0.92
        case 50, 20, 10: 0.78
        default: 0.64
        }
    }

    private var rotationGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = (yaw, pitch)
                }
                guard let origin = dragOrigin else { return }
                yaw = max(-72, min(72, origin.yaw + Double(value.translation.width) * 0.28))
                pitch = max(-20, min(26, origin.pitch - Double(value.translation.height) * 0.18))
            }
            .onEnded { _ in
                dragOrigin = nil
                withAnimation(AppMotion.spring) {
                    yaw = max(-72, min(72, yaw))
                    pitch = max(-20, min(26, pitch))
                }
            }
    }

    private var accessibilityLabel: String {
        guard !groups.isEmpty else { return "金额为零，未生成现钞" }
        let total = CashBreakdown.totalNotes(groups)
        let pieces = groups.map { "\($0.denomination.name) \($0.count) 张" }.joined(separator: "，")
        return "共 \(total) 张：\(pieces)。上下拖动可按高度旋转，查看现钞组合。"
    }
}

private struct CashStackView: View {
    let group: CashGroup
    let width: CGFloat
    let palette: AppPalette
    let yaw: Double
    let pitch: Double
    let tilt: Double

    private var image: UIImage? {
        guard let path = Bundle.main.path(
            forResource: group.denomination.imageName,
            ofType: "jpg",
            inDirectory: "Notes"
        ) else { return nil }
        return UIImage(contentsOfFile: path)
    }

    private var aspect: CGFloat {
        guard let image, image.size.height > 0 else { return 640 / 306 }
        return image.size.width / image.size.height
    }

    private var layers: Int {
        min(max(group.count, 1), 7)
    }

    var body: some View {
        ZStack {
            if let image {
                ForEach(0..<layers, id: \.self) { layer in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: width)
                        .overlay(
                            Rectangle()
                                .stroke(palette.isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10), lineWidth: 0.5)
                        )
                        .offset(
                            x: CGFloat(layer) * 0.9,
                            y: -CGFloat(layer) * max(0.8, min(2.0, 8.0 / CGFloat(layers)))
                        )
                        .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.62)
                        .rotation3DEffect(.degrees(pitch), axis: (x: 1, y: 0, z: 0), perspective: 0.62)
                        .rotationEffect(.degrees(tilt))
                        .shadow(color: .black.opacity(0.30), radius: 7, x: 0, y: 9)
                }
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(palette.surface2)
                    .frame(width: width, height: width / aspect)
            }

            if group.count >= 100 {
                Rectangle()
                    .fill(palette.isDark ? Color(hex: 0xE8DFC9).opacity(0.9) : Color(hex: 0x6B5B3B).opacity(0.75))
                    .frame(width: width * 0.13, height: width / aspect * 1.12)
                    .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.62)
                    .rotation3DEffect(.degrees(pitch), axis: (x: 1, y: 0, z: 0), perspective: 0.62)
                    .rotationEffect(.degrees(tilt))
            }
        }
        .frame(width: width, height: width / aspect + 8)
    }
}
