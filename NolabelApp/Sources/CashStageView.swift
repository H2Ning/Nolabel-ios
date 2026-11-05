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
    @State private var motionBlur: Double = 0
    @State private var lastYawSample: (yaw: Double, time: CFTimeInterval)?
    @State private var blurDecayTask: Task<Void, Never>?

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
                        ZStack {
                            CashScene3DView(
                                source: source,
                                mode: mode,
                                yaw: yaw,
                                pitch: pitch,
                                isDark: palette.isDark,
                                onReady: signalReady
                            )

                            // Blurred copies, each masked so a stack stays
                            // sharp on its own axis and smears outward.
                            blurredOverlay(in: proxy.size)
                        }
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
                blurDecayTask?.cancel()
            }
            .onChange(of: mode) { _, newMode in
                momentum.stop()
                lastDetentYaw = yaw
                if newMode == 3 {
                    signalReady()
                }
            }
            .onChange(of: yaw) { _, newYaw in
                updateMotionBlur(newYaw)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("轻点停止旋转，右下角按钮切换摆放方式")
            .accessibilityAction {
                momentum.stop()
            }
        }
    }

    private struct GroupAxis {
        let x: CGFloat
        let count: Int
    }

    private struct BlurTier: Identifiable {
        let id: Int
        let scale: Double
        let centers: [CGFloat]
    }

    /// Blurred copies of the scene. Grouped stacks are split into size tiers
    /// so a taller stack gets a wider smear; every tier is masked to its own
    /// stacks' bands, keeping each one sharp on its own axis.
    @ViewBuilder
    private func blurredOverlay(in size: CGSize) -> some View {
        let axes = groupAxes(in: size)
        let tiers = blurTiers(axes: axes)
        let boost = blurSizeBoost
        if tiers.isEmpty {
            blurredScene(radius: motionBlur * boost, mask: globalMotionBlurMask)
        } else {
            let all = axes.map(\.x)
            ForEach(tiers) { tier in
                blurredScene(
                    radius: motionBlur * boost * tier.scale,
                    mask: motionBlurMask(centers: tier.centers, all: all)
                )
            }
        }
    }

    private func blurredScene<M: View>(radius: Double, mask: M) -> some View {
        CashScene3DView(
            source: source,
            mode: mode,
            yaw: yaw,
            pitch: pitch,
            isDark: palette.isDark,
            onReady: {}
        )
        .blur(radius: radius)
        .mask(mask)
        .opacity(motionBlur > 0.01 ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Larger models move their outer edge farther at the same angular speed,
    /// so the base radius grows with the tallest stack.
    private var blurSizeBoost: Double {
        guard let maxCount = groups.map(\.count).max(), maxCount > 0 else { return 1 }
        return min(1.15, max(0.75, 0.75 + 0.4 * min(1, Double(maxCount) / 60)))
    }

    private func motionBlurMask(centers: [CGFloat], all: [CGFloat]) -> some View {
        Canvas { context, canvasSize in
            for center in centers {
                guard let index = all.firstIndex(of: center) else { continue }
                let left = index == 0 ? 0 : (all[index - 1] + center) / 2
                let right = index == all.count - 1 ? canvasSize.width : (center + all[index + 1]) / 2
                let width = max(right - left, 1)
                let clearHalf = min(0.30, max(0.10, 34 / width))
                let gradient = Gradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: 0.18),
                    .init(color: .clear, location: 0.5 - clearHalf),
                    .init(color: .clear, location: 0.5 + clearHalf),
                    .init(color: .white, location: 0.82),
                    .init(color: .white, location: 1)
                ])
                context.fill(
                    Path(CGRect(x: left, y: 0, width: width, height: canvasSize.height)),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: left, y: 0),
                        endPoint: CGPoint(x: right, y: 0)
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }

    private var globalMotionBlurMask: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0.0),
                .init(color: .white, location: 0.20),
                .init(color: .clear, location: 0.42),
                .init(color: .clear, location: 0.58),
                .init(color: .white, location: 0.80),
                .init(color: .white, location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Screen-space x of each group's own vertical axis, following the same
    /// yaw/pitch rotation the 3D canvas applies. Groups in different rows
    /// project differently, so each row is computed separately.
    private func groupAxes(in size: CGSize) -> [GroupAxis] {
        guard mode == 2, groups.count > 1, size.width > 1, size.height > 1 else {
            return []
        }
        let count = groups.count
        let columns = count <= 3 ? count : (count == 4 ? 2 : 3)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let padX: CGFloat = 10
        let gapX: CGFloat = 6
        let cellWidth = (size.width - padX * 2 - gapX * CGFloat(columns - 1)) / CGFloat(columns)
        let rowBase: CGFloat = rows == 1 ? 0.56 : (rows == 2 ? 0.30 : 0.26)
        let rowGap: CGFloat = rows == 1 ? 0 : (rows == 2 ? 0.36 : 0.20)

        let yawRad = yaw * .pi / 180
        let pitchRad = pitch * .pi / 180
        let anchor = CGPoint(x: size.width / 2, y: size.height * 0.44)
        let cosYaw = CGFloat(cos(yawRad))
        let sinYaw = CGFloat(sin(yawRad))
        let cosPitch = CGFloat(cos(pitchRad))

        var axes: [GroupAxis] = []
        for index in 0..<count {
            let row = index / columns
            let column = index % columns
            let rowCount = Swift.min(columns, count - row * columns)
            let rowOffset = CGFloat(columns - rowCount) * (cellWidth + gapX) / 2
            let cellLeft = padX + rowOffset + CGFloat(column) * (cellWidth + gapX)
            let cellCenter = cellLeft + cellWidth / 2
            let baseY = size.height * (rowBase + CGFloat(row) * rowGap)
            let relX = cellCenter - anchor.x
            let relY = baseY - anchor.y
            axes.append(GroupAxis(
                x: anchor.x + relX * cosYaw - relY * cosPitch * sinYaw,
                count: groups[index].count
            ))
        }
        return axes.sorted { $0.x < $1.x }
    }

    /// Three size tiers by note count, each with its own radius scale.
    private func blurTiers(axes: [GroupAxis]) -> [BlurTier] {
        guard axes.count > 1, let maxCount = axes.map(\.count).max(), maxCount > 0 else {
            return []
        }
        var buckets: [[CGFloat]] = [[], [], []]
        for axis in axes {
            let ratio = Double(axis.count) / Double(maxCount)
            let bucket = ratio >= 2.0 / 3.0 ? 2 : (ratio >= 1.0 / 3.0 ? 1 : 0)
            buckets[bucket].append(axis.x)
        }
        let scales = [0.55, 0.78, 1.0]
        return (0..<3).compactMap { index in
            guard !buckets[index].isEmpty else { return nil }
            return BlurTier(id: index, scale: scales[index], centers: buckets[index].sorted())
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

    /// A small Gaussian blur that follows the angular speed of the stage.
    /// It is not a true directional motion blur, but at 0–4pt it reads as one
    /// while the notes are spinning and disappears as soon as they settle.
    private func updateMotionBlur(_ newYaw: Double) {
        let now = CACurrentMediaTime()
        defer { lastYawSample = (newYaw, now) }
        guard let last = lastYawSample else { return }

        let dt = max(now - last.time, 1.0 / 120.0)
        let degreesPerSecond = abs(newYaw - last.yaw) / dt
        let target = min(10.0, max(0, (degreesPerSecond - 40) / 90))
        motionBlur = target

        blurDecayTask?.cancel()
        blurDecayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                motionBlur = 0
            }
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
