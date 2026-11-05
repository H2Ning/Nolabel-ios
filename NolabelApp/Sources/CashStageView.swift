import QuartzCore
import SwiftUI
import UIKit

struct CashStageView: View {
    let source: CashSceneSource
    let palette: AppPalette
    @Binding var yaw: Double
    @Binding var pitch: Double
    let mode: Int
    let onSelectMode: (Int) -> Void
    let onReady: () -> Void

    @StateObject private var momentum = CashRotationMomentum()
    @State private var didSignalReady = false
    @State private var dragOrigin: (yaw: Double, pitch: Double)?
    @State private var lastDragTime: CFTimeInterval = 0
    @State private var lastDragX: CGFloat = 0
    @State private var dragVelocityX: CGFloat = 0
    @State private var lastDetentYaw: Double?

    private var groups: [CashGroup] {
        switch source {
        case .cents(let cents): return CashBreakdown.groups(for: cents)
        case .groups(let groups): return groups
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                stageBackground
                grid

                if !groups.isEmpty {
                    if mode == 3 {
                        CashNoteGrid(source: source, palette: palette)
                    } else {
                        CashScene3DView(
                            source: source,
                            mode: mode,
                            yaw: yaw,
                            pitch: pitch,
                            isDark: palette.isDark,
                            onReady: signalReady
                        )
                    }
                }

                if !groups.isEmpty {
                    modeBadge
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.bottom, 5)
                        .padding(.trailing, 12)
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
                    if !groups.isEmpty {
                        momentum.stop()
                    }
                }
            )
            .animation(.easeOut(duration: 0.18), value: mode)
            .onAppear {
                momentum.onDelta = { delta in
                    yaw += delta
                    trackRotationDetents()
                }
                if groups.isEmpty || mode == 3 {
                    signalReady()
                }
            }
            .onDisappear {
                momentum.stop()
            }
            .onChange(of: mode) { _, newMode in
                momentum.stop()
                lastDetentYaw = yaw
                if newMode == 3 {
                    signalReady()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("轻点停止旋转，右下角按钮切换摆放方式")
            .accessibilityAction {
                momentum.stop()
            }
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
        Menu {
            ForEach([1, 2, 3], id: \.self) { value in
                Button {
                    momentum.stop()
                    onSelectMode(value)
                } label: {
                    if value == mode {
                        Label(modeLabel(for: value), systemImage: "checkmark")
                    } else {
                        Text(modeLabel(for: value))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(modeLabel)
                Image(systemName: "chevron.up.chevron.down")
                    .scalableFont(8, weight: .bold)
            }
            .scalableFont(11, weight: .semibold)
            .foregroundStyle(palette.ink2)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(
                palette.isDark ? Color.black.opacity(0.22) : Color.white.opacity(0.46),
                in: Capsule()
            )
            .overlay(Capsule().stroke(palette.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("现金摆放方式，当前\(modeLabel)")
        .accessibilityHint("打开菜单选择整叠、分组或展开")
    }

    private func signalReady() {
        guard !didSignalReady else { return }
        didSignalReady = true
        onReady()
    }

    private var modeLabel: String { modeLabel(for: mode) }

    private func modeLabel(for value: Int) -> String {
        switch value {
        case 2: "分组"
        case 3: "展开"
        default: "整叠"
        }
    }

    private func trackRotationDetents() {
        guard let last = lastDetentYaw else {
            lastDetentYaw = yaw
            return
        }
        let distance = abs(yaw - last)
        guard distance >= 15 else { return }
        let count = min(3, Int(distance / 15))
        for _ in 0..<count {
            Haptics.rotationDetent()
        }
        lastDetentYaw = yaw
    }

    private var rotationGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragOrigin == nil {
                    momentum.stop()
                    dragOrigin = (yaw, pitch)
                    lastDetentYaw = yaw
                    dragVelocityX = 0
                    lastDragX = 0
                    lastDragTime = CACurrentMediaTime()
                }
                guard let origin = dragOrigin else { return }

                let now = CACurrentMediaTime()
                let deltaTime = now - lastDragTime
                if deltaTime > 0.006 {
                    let instant = Double(value.translation.width - lastDragX) / deltaTime
                    dragVelocityX = dragVelocityX * 0.55 + CGFloat(instant) * 0.45
                    lastDragX = value.translation.width
                    lastDragTime = now
                }

                // Horizontal rotation is deliberately unbounded.
                yaw = origin.yaw - Double(value.translation.width) * 0.55
                pitch = max(26, min(66, origin.pitch - Double(value.translation.height) * 0.30))
                trackRotationDetents()
            }
            .onEnded { _ in
                dragOrigin = nil
                let idle = CACurrentMediaTime() - lastDragTime
                guard idle < 0.12 else {
                    dragVelocityX = 0
                    return
                }
                momentum.start(velocity: -Double(dragVelocityX) * 0.55)
            }
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
        return "共 \(total) 张：\(pieces)。当前\(modeText)。左右拖动可旋转，轻点停止旋转，右下角切换摆放方式。"
    }
}

private struct CashNoteGrid: View {
    let source: CashSceneSource
    let palette: AppPalette

    private var groups: [CashGroup] {
        switch source {
        case .cents(let cents): return CashBreakdown.groups(for: cents)
        case .groups(let groups): return groups
        }
    }

    private var notes: [Denomination] {
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
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 56)
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
