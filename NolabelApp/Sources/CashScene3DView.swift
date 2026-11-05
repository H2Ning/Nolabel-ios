import SwiftUI
import UIKit

struct CashScene3DView: UIViewRepresentable {
    let source: CashSceneSource
    let mode: Int
    let yaw: Double
    let pitch: Double
    let isDark: Bool
    var onReady: (() -> Void)? = nil

    func makeUIView(context: Context) -> CashSceneCanvas {
        let view = CashSceneCanvas()
        view.isUserInteractionEnabled = false
        view.onReady = onReady
        return view
    }

    func updateUIView(_ view: CashSceneCanvas, context: Context) {
        view.onReady = onReady
        view.update(source: source, mode: mode, yaw: yaw, pitch: pitch, isDark: isDark)
    }
}

final class CashSceneCanvas: UIView {
    private let contentLayer = CATransformLayer()
    private var nodes: [ItemNode] = []
    private var sceneKey = ""
    private var sceneSize: CGSize = .zero
    private var lastSource: CashSceneSource = .cents(0)
    private var lastMode = 1
    private var yaw: Double = Double(CashSceneLayout.defaultYaw)
    private var pitch: Double = Double(CashSceneLayout.packageTilt)
    private var hasSource = false
    private var readySignaled = false
    private var isDark = false
    private var pileHeightCentroid: CGFloat = 0
    var onReady: (() -> Void)?

    private struct ItemNode {
        let layer: CALayer
        let x: CGFloat
        let y: CGFloat
    }

    private enum NoteEdge: String {
        case left
        case right
        case top
        case bottom
    }


    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        layer.masksToBounds = true
        contentLayer.masksToBounds = false
        contentLayer.anchorPoint = CGPoint(x: 0.5, y: 0.44)
        contentLayer.sublayerTransform = CATransform3DIdentity
        contentLayer.sublayerTransform.m34 = -1 / CashSceneLayout.perspective
        contentLayer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "transform": NSNull(),
            "contents": NSNull(),
            "opacity": NSNull()
        ]
        layer.addSublayer(contentLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        contentLayer.position = CGPoint(x: bounds.width / 2, y: bounds.height * 0.44)
        if bounds.size != sceneSize {
            sceneSize = bounds.size
            rebuild(source: lastSource, mode: lastMode)
        }
        signalReadyIfNeeded()
    }

    private func signalReadyIfNeeded() {
        guard !readySignaled, hasSource, bounds.width > 1, bounds.height > 1 else { return }
        readySignaled = true
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async {
                self?.onReady?()
            }
        }
    }

    func update(source: CashSceneSource, mode: Int, yaw: Double, pitch: Double, isDark: Bool) {
        self.yaw = yaw
        self.pitch = pitch
        self.isDark = isDark
        hasSource = true
        let nextKey = "\(source.key)|\(mode)"
        if nextKey != sceneKey || bounds.size != sceneSize {
            sceneKey = nextKey
            lastSource = source
            lastMode = mode
            rebuild(source: source, mode: mode)
        }
        updateTransforms()
        signalReadyIfNeeded()
    }

    private func rebuild(source: CashSceneSource, mode: Int) {
        let size = bounds.size
        sceneSize = size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        nodes.removeAll(keepingCapacity: true)

        guard size.width > 1, size.height > 1 else {
            CATransaction.commit()
            return
        }

        let spec = CashSceneLayout.spec(source: source, mode: mode, size: size)
        pileHeightCentroid = Self.heightCentroid(of: spec.items.filter { $0.kind == .pile })
        for item in spec.items {
            guard let node = makeNode(for: item) else { continue }
            contentLayer.addSublayer(node.layer)
            nodes.append(node)
        }
        CATransaction.commit()
        updateTransforms()
    }

    private func updateTransforms() {
        guard !nodes.isEmpty, sceneSize.width > 1 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for node in nodes {
            node.layer.transform = worldTransform(x: node.x, y: node.y)
        }
        CATransaction.commit()
    }

    // MARK: - Item construction

    private func makeNode(for item: CashItemSpec) -> ItemNode? {
        let container = CATransformLayer()
        container.bounds = .zero
        container.position = .zero
        container.anchorPoint = .zero
        container.masksToBounds = false
        container.actions = Self.noActions

        addGroundShadow(to: container, width: item.width, depth: item.depth)

        switch item.kind {
        case .box:
            addBox(to: container, item: item)
        default:
            for (index, layerSpec) in item.layers.enumerated() {
                addNoteLayer(
                    to: container,
                    spec: layerSpec,
                    isTopLayer: index == item.layers.count - 1,
                    showBand: item.showBand,
                    showSeal: item.showSeal
                )
            }
        }

        return ItemNode(layer: container, x: item.x, y: item.y)
    }

    private func addNoteLayer(
        to container: CALayer,
        spec: CashLayerSpec,
        isTopLayer: Bool,
        showBand: Bool,
        showSeal: Bool
    ) {
        let denom = spec.denomination
        let width = spec.width
        let depth = spec.depth
        let thickness = spec.thickness
        let zBottom = spec.z
        let zTop = zBottom + thickness
        let zCenter = zBottom + thickness / 2

        let shadowColor = UIColor(hex: denom.sideDarkColor)
        let leftSide = sideImage(
            denom: denom,
            width: thickness,
            height: depth,
            spacing: spec.noteStep,
            vertical: true,
            edge: .left
        )
        let rightSide = sideImage(
            denom: denom,
            width: thickness,
            height: depth,
            spacing: spec.noteStep,
            vertical: true,
            edge: .right
        )
        let topSideImage = sideImage(
            denom: denom,
            width: width,
            height: thickness,
            spacing: spec.noteStep,
            vertical: false,
            edge: .top
        )
        let bottomSideImage = sideImage(
            denom: denom,
            width: width,
            height: thickness,
            spacing: spec.noteStep,
            vertical: false,
            edge: .bottom,
            flipHorizontal: true
        )

        // Exposed back face of the bottom of the cuboid.
        let back = CALayer()
        back.bounds = CGRect(x: 0, y: 0, width: width, height: depth)
        back.position = .zero
        back.zPosition = zBottom
        back.backgroundColor = shadowColor.cgColor
        back.transform = rotationY(.pi)
        back.isDoubleSided = false
        back.actions = Self.noActions
        container.addSublayer(back)

        let left = sideFace(
            image: leftSide,
            width: thickness,
            height: depth,
            center: CGPoint(x: -width / 2, y: 0),
            z: zCenter,
            rotation: rotationY(-.pi / 2)
        )
        container.addSublayer(left)

        let right = sideFace(
            image: rightSide,
            width: thickness,
            height: depth,
            center: CGPoint(x: width / 2, y: 0),
            z: zCenter,
            rotation: rotationY(.pi / 2)
        )
        container.addSublayer(right)

        let topSide = sideFace(
            image: topSideImage,
            width: width,
            height: thickness,
            center: CGPoint(x: 0, y: -depth / 2),
            z: zCenter,
            rotation: rotationX(.pi / 2)
        )
        container.addSublayer(topSide)

        let bottomSide = sideFace(
            image: bottomSideImage,
            width: width,
            height: thickness,
            center: CGPoint(x: 0, y: depth / 2),
            z: zCenter,
            rotation: rotationX(-.pi / 2)
        )
        container.addSublayer(bottomSide)

        let face = CALayer()
        face.bounds = CGRect(x: 0, y: 0, width: width, height: depth)
        face.position = .zero
        face.zPosition = zTop
        face.cornerRadius = 1
        face.masksToBounds = true
        face.contents = noteImage(denom.imageName)?.cgImage
        face.contentsGravity = .resizeAspectFill
        face.contentsScale = UIScreen.main.scale
        face.borderWidth = 0.4
        face.borderColor = UIColor.black.withAlphaComponent(0.14).cgColor
        face.isDoubleSided = false
        face.actions = Self.noActions
        container.addSublayer(face)

        if showBand {
            addBand(to: face, width: width, depth: depth)
            addBandEdges(
                to: container,
                width: width,
                height: thickness,
                depth: depth,
                zCenter: zCenter
            )
        }
        if showSeal, isTopLayer {
            addSeal(to: face, width: width, depth: depth)
        }
    }

    private func sideFace(
        image: CGImage?,
        width: CGFloat,
        height: CGFloat,
        center: CGPoint,
        z: CGFloat,
        rotation: CATransform3D
    ) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: max(0.5, width), height: max(0.5, height))
        layer.position = center
        layer.zPosition = z
        layer.contents = image
        layer.contentsGravity = .resize
        layer.contentsScale = UIScreen.main.scale
        layer.transform = rotation
        layer.isDoubleSided = false
        layer.actions = Self.noActions
        return layer
    }

    private func addBand(to face: CALayer, width: CGFloat, depth: CGFloat) {
        let bandWidth = max(2, width * 0.10)
        let ratio: CGFloat = 0.5
        let topBand = CALayer()
        topBand.bounds = CGRect(x: 0, y: 0, width: bandWidth, height: depth)
        topBand.position = CGPoint(x: width * ratio, y: depth * 0.5)
        topBand.backgroundColor = UIColor(white: 0.965, alpha: 0.97).cgColor
        topBand.shadowColor = UIColor.black.cgColor
        topBand.shadowOpacity = 0.16
        topBand.shadowRadius = 1.5
        topBand.shadowOffset = CGSize(width: 0, height: 1)
        topBand.zPosition = 0.2
        topBand.actions = Self.noActions
        face.addSublayer(topBand)

        // The bound edge of a paper bundle is a little lighter than the printed face.
        let leftMargin = CALayer()
        leftMargin.bounds = CGRect(x: 0, y: 0, width: 1, height: depth)
        leftMargin.position = CGPoint(x: 0.75, y: depth / 2)
        leftMargin.backgroundColor = UIColor(white: 0.99, alpha: 0.72).cgColor
        leftMargin.zPosition = 0.12
        leftMargin.actions = Self.noActions
        face.addSublayer(leftMargin)

        let rightMargin = CALayer()
        rightMargin.bounds = CGRect(x: 0, y: 0, width: 1, height: depth)
        rightMargin.position = CGPoint(x: width - 0.75, y: depth / 2)
        rightMargin.backgroundColor = UIColor(white: 0.99, alpha: 0.72).cgColor
        rightMargin.zPosition = 0.12
        rightMargin.actions = Self.noActions
        face.addSublayer(rightMargin)
    }

    private func addBandEdges(
        to container: CALayer,
        width: CGFloat,
        height: CGFloat,
        depth: CGFloat,
        zCenter: CGFloat
    ) {
        let bandWidth = max(2, width * 0.10)
        let faceSize = CGRect(x: 0, y: 0, width: width, height: height)

        let front = CALayer()
        front.bounds = faceSize
        front.position = CGPoint(x: 0, y: depth / 2 + 0.05)
        front.zPosition = zCenter
        front.transform = rotationX(-.pi / 2)
        front.isDoubleSided = false
        front.actions = Self.noActions
        container.addSublayer(front)

        let back = CALayer()
        back.bounds = faceSize
        back.position = CGPoint(x: 0, y: -(depth / 2 + 0.05))
        back.zPosition = zCenter
        back.transform = rotationX(.pi / 2)
        back.isDoubleSided = false
        back.actions = Self.noActions
        container.addSublayer(back)

        addFrontBand(
            to: front,
            width: width,
            bandWidth: bandWidth,
            ratio: 0.5,
            y: height / 2,
            height: height
        )
        addFrontBand(
            to: back,
            width: width,
            bandWidth: bandWidth,
            ratio: 0.5,
            y: height / 2,
            height: height
        )
    }

    private func addFrontBand(
        to face: CALayer,
        width: CGFloat,
        bandWidth: CGFloat,
        ratio: CGFloat,
        y: CGFloat,
        height: CGFloat
    ) {
        let band = CALayer()
        band.bounds = CGRect(x: 0, y: 0, width: bandWidth, height: height)
        band.position = CGPoint(x: width * ratio, y: y)
        band.backgroundColor = UIColor(white: 0.965, alpha: 0.96).cgColor
        band.actions = Self.noActions
        face.addSublayer(band)
    }

    private func addSeal(to face: CALayer, width: CGFloat, depth: CGFloat) {
        let marginX = width * 0.035
        let marginY = depth * 0.055
        let sealWidth = max(24, width - marginX * 2)
        let sealHeight = max(18, depth - marginY * 2)
        let seal = CALayer()
        seal.bounds = CGRect(x: 0, y: 0, width: sealWidth, height: sealHeight)
        seal.position = CGPoint(x: width / 2, y: depth / 2)
        seal.backgroundColor = UIColor(white: 0.988, alpha: 0.985).cgColor
        seal.cornerRadius = 1
        seal.borderWidth = 0.6
        seal.borderColor = UIColor(hex: 0xB2443A).withAlphaComponent(0.42).cgColor
        seal.zPosition = 0.5
        seal.actions = Self.noActions
        face.addSublayer(seal)

        let ink = UIColor(hex: 0x33302B)
        let red = UIColor(hex: 0xB2443A)
        let blue = UIColor(hex: 0x3A5C86)

        if let icon = noteImage("100") {
            let iconWidth = sealWidth * 0.17
            let iconHeight = iconWidth * 314.0 / 640.0
            let iconLayer = CALayer()
            iconLayer.bounds = CGRect(x: 0, y: 0, width: iconWidth, height: iconHeight)
            iconLayer.position = CGPoint(x: sealWidth * 0.14, y: sealHeight * 0.58)
            iconLayer.contents = icon.cgImage
            iconLayer.contentsGravity = .resizeAspectFill
            iconLayer.contentsScale = UIScreen.main.scale
            iconLayer.borderWidth = 0.4
            iconLayer.borderColor = UIColor.black.withAlphaComponent(0.18).cgColor
            iconLayer.actions = Self.noActions
            seal.addSublayer(iconLayer)
        }

        let bank = textLayer(
            "\u{4E2D}\u{56FD}\u{94F6}\u{884C}",
            size: max(3.6, sealWidth * 0.050),
            color: blue,
            weight: .semibold
        )
        bank.frame = CGRect(x: 0, y: sealHeight * 0.07, width: sealWidth, height: sealHeight * 0.16)
        seal.addSublayer(bank)

        let amount = textLayer(
            "\u{58F9}\u{62FE}\u{4E07}\u{5143}\u{6574}",
            size: max(8, sealWidth * 0.125),
            color: ink,
            weight: .bold
        )
        amount.frame = CGRect(x: 0, y: sealHeight * 0.27, width: sealWidth, height: sealHeight * 0.36)
        seal.addSublayer(amount)

        let stamp = textLayer(
            "\u{5C01}\u{7B7E}",
            size: max(3.4, sealWidth * 0.045),
            color: red,
            weight: .semibold
        )
        stamp.frame = CGRect(x: sealWidth * 0.72, y: sealHeight * 0.06, width: sealWidth * 0.24, height: sealHeight * 0.15)
        seal.addSublayer(stamp)

        let foot = textLayer(
            "\u{5E74}  \u{6708}  \u{65E5}    \u{590D}\u{6838}\u{5458} 07225    \u{5C01}\u{6346}\u{5458} 04325",
            size: max(2.6, sealWidth * 0.034),
            color: UIColor(hex: 0x6B5B4B),
            weight: .regular
        )
        foot.frame = CGRect(x: 0, y: sealHeight * 0.80, width: sealWidth, height: sealHeight * 0.13)
        seal.addSublayer(foot)

        let round = CAShapeLayer()
        let diameter = min(sealHeight * 0.34, sealWidth * 0.18)
        round.path = UIBezierPath(ovalIn: CGRect(
            x: sealWidth * 0.74,
            y: sealHeight * 0.48,
            width: diameter,
            height: diameter
        )).cgPath
        round.fillColor = UIColor.clear.cgColor
        round.strokeColor = red.withAlphaComponent(0.55).cgColor
        round.lineWidth = max(0.6, diameter * 0.06)
        round.actions = Self.noActions
        seal.addSublayer(round)

        let sterile = textLayer(
            "\u{5DF2}\u{6D88}\u{6BD2}",
            size: max(2.8, diameter * 0.22),
            color: red.withAlphaComponent(0.72),
            weight: .medium
        )
        sterile.frame = CGRect(
            x: sealWidth * 0.74,
            y: sealHeight * 0.48 + diameter * 0.38,
            width: diameter,
            height: diameter * 0.30
        )
        seal.addSublayer(sterile)
    }

    private func addBox(to container: CALayer, item: CashItemSpec) {
        let width = item.width
        let depth = item.depth
        let height = item.height
        let frontColor = UIColor(hex: 0xBE8F56)
        let topColor = UIColor(hex: 0xC99A5E)
        let backColor = UIColor(hex: 0x9C7447)
        let sideColor = UIColor(hex: 0xA97C4D)
        let tape = UIColor(hex: 0xE8C77A)

        let top = CALayer()
        top.bounds = CGRect(x: 0, y: 0, width: width, height: depth)
        top.position = .zero
        top.zPosition = height
        top.backgroundColor = topColor.cgColor
        top.contents = cardboardImage(width: width, height: depth, vertical: false)
        top.contentsGravity = .resize
        top.contentsScale = UIScreen.main.scale
        top.borderWidth = 0.6
        top.borderColor = UIColor.black.withAlphaComponent(0.18).cgColor
        top.isDoubleSided = false
        top.actions = Self.noActions
        container.addSublayer(top)

        let front = CALayer()
        front.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        front.position = CGPoint(x: 0, y: depth / 2)
        front.zPosition = height / 2
        front.backgroundColor = frontColor.cgColor
        front.contents = cardboardImage(width: width, height: height, vertical: true)
        front.contentsGravity = .resize
        front.contentsScale = UIScreen.main.scale
        front.transform = rotationX(-.pi / 2)
        front.isDoubleSided = false
        front.actions = Self.noActions
        container.addSublayer(front)

        let back = CALayer()
        back.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        back.position = CGPoint(x: 0, y: -depth / 2)
        back.zPosition = height / 2
        back.backgroundColor = backColor.cgColor
        back.contents = cardboardImage(width: width, height: height, vertical: true)
        back.contentsGravity = .resize
        back.contentsScale = UIScreen.main.scale
        back.transform = rotationX(.pi / 2)
        back.isDoubleSided = false
        back.actions = Self.noActions
        container.addSublayer(back)

        let left = CALayer()
        left.bounds = CGRect(x: 0, y: 0, width: height, height: depth)
        left.position = CGPoint(x: -width / 2, y: 0)
        left.zPosition = height / 2
        left.backgroundColor = sideColor.cgColor
        left.contents = cardboardImage(width: height, height: depth, vertical: true)
        left.contentsGravity = .resize
        left.contentsScale = UIScreen.main.scale
        left.transform = rotationY(-.pi / 2)
        left.isDoubleSided = false
        left.actions = Self.noActions
        container.addSublayer(left)

        let right = CALayer()
        right.bounds = CGRect(x: 0, y: 0, width: height, height: depth)
        right.position = CGPoint(x: width / 2, y: 0)
        right.zPosition = height / 2
        right.backgroundColor = sideColor.cgColor
        right.contents = cardboardImage(width: height, height: depth, vertical: true)
        right.contentsGravity = .resize
        right.contentsScale = UIScreen.main.scale
        right.transform = rotationY(.pi / 2)
        right.isDoubleSided = false
        right.actions = Self.noActions
        container.addSublayer(right)

        let tapeWidth = max(4, width * 0.18)
        let topTape = CALayer()
        topTape.bounds = CGRect(x: 0, y: 0, width: width, height: tapeWidth)
        topTape.position = CGPoint(x: width / 2, y: depth / 2)
        topTape.backgroundColor = tape.withAlphaComponent(0.96).cgColor
        topTape.zPosition = 0.2
        topTape.actions = Self.noActions
        addTapeGloss(to: topTape)
        top.addSublayer(topTape)

        for isRight in [false, true] {
            let sideTape = CALayer()
            sideTape.bounds = CGRect(x: 0, y: 0, width: max(2, height * 0.32), height: tapeWidth)
            sideTape.position = CGPoint(x: isRight ? height * 0.18 : height * 0.82, y: depth * 0.5)
            sideTape.backgroundColor = tape.withAlphaComponent(0.92).cgColor
            sideTape.zPosition = 0.2
            sideTape.actions = Self.noActions
            addTapeGloss(to: sideTape)
            (isRight ? right : left).addSublayer(sideTape)
        }

        guard let image = noteImage("100") else { return }
        let stickerWidth = width * 0.36
        let stickerHeight = stickerWidth * 314.0 / 640.0
        let sticker = CALayer()
        sticker.bounds = CGRect(x: 0, y: 0, width: stickerWidth, height: stickerHeight)
        sticker.position = CGPoint(x: width / 2, y: height / 2)
        sticker.contents = image.cgImage
        sticker.contentsGravity = .resizeAspectFill
        sticker.contentsScale = UIScreen.main.scale
        sticker.cornerRadius = 1
        sticker.masksToBounds = true
        sticker.borderWidth = 0.5
        sticker.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        sticker.zPosition = 0.3
        sticker.actions = Self.noActions
        front.addSublayer(sticker)
    }

    private func cardboardImage(width: CGFloat, height: CGFloat, vertical: Bool) -> CGImage? {
        let scale = UIScreen.main.scale
        let pixelWidth = max(1, Int((width * scale).rounded()))
        let pixelHeight = max(1, Int((height * scale).rounded()))
        let key = "box|\(pixelWidth)|\(pixelHeight)|\(vertical)" as NSString
        if let cached = Self.boxImages.object(forKey: key) {
            return cached.cgImage
        }

        let size = CGSize(width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale)
        let base = UIColor(hex: 0xBE8F56)
        let line = UIColor(hex: 0x8C673E)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(base.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            let colors = [
                UIColor.white.withAlphaComponent(0.14).cgColor,
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.12).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.4, 1]) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }

            cg.setStrokeColor(line.withAlphaComponent(0.18).cgColor)
            cg.setLineWidth(0.5)
            let step: CGFloat = 3
            if vertical {
                var x: CGFloat = 0
                while x <= size.width {
                    cg.move(to: CGPoint(x: x, y: 0))
                    cg.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
            } else {
                var y: CGFloat = 0
                while y <= size.height {
                    cg.move(to: CGPoint(x: 0, y: y))
                    cg.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
            }
            cg.strokePath()
        }
        Self.boxImages.setObject(image, forKey: key)
        return image.cgImage
    }

    private func addTapeGloss(to tape: CALayer) {
        let gloss = CAGradientLayer()
        gloss.frame = tape.bounds
        gloss.colors = [
            UIColor(hex: 0xF1D486).cgColor,
            UIColor(hex: 0xFFEAB0).withAlphaComponent(0.96).cgColor,
            UIColor(hex: 0xD8B05B).cgColor
        ]
        gloss.locations = [0, 0.45, 1]
        gloss.startPoint = CGPoint(x: 0, y: 0)
        gloss.endPoint = CGPoint(x: 0, y: 1)
        gloss.actions = Self.noActions
        tape.addSublayer(gloss)
    }

    private func addGroundShadow(to container: CALayer, width: CGFloat, depth: CGFloat) {
        let shadow = CALayer()
        // Keep it a narrow contact halo under the paper. A larger shadow looks
        // like a second banknote when the scene is tilted in perspective.
        shadow.bounds = CGRect(x: 0, y: 0, width: max(16, width * 0.84), height: max(16, depth * 0.88))
        shadow.position = .zero
        shadow.zPosition = -1
        shadow.contents = Self.shadowImage
        shadow.contentsGravity = .resize
        shadow.opacity = isDark ? 0.40 : 0.18
        shadow.actions = Self.noActions
        container.addSublayer(shadow)
    }

    private func textLayer(_ text: String, size: CGFloat, color: UIColor, weight: UIFont.Weight) -> CATextLayer {
        let layer = CATextLayer()
        layer.string = text
        layer.font = UIFont.systemFont(ofSize: size, weight: weight)
        layer.fontSize = size
        layer.foregroundColor = color.cgColor
        layer.alignmentMode = .center
        layer.isWrapped = false
        layer.truncationMode = .none
        layer.contentsScale = UIScreen.main.scale
        layer.actions = Self.noActions
        return layer
    }

    // MARK: - Assets

    private func noteImage(_ name: String) -> UIImage? {
        if let cached = Self.noteImages.object(forKey: name as NSString) {
            return cached
        }
        guard let path = Bundle.main.path(forResource: name, ofType: "jpg", inDirectory: "Notes"),
              let image = UIImage(contentsOfFile: path) else {
            return nil
        }
        Self.noteImages.setObject(image, forKey: name as NSString)
        return image
    }

    private func sideImage(
        denom: Denomination,
        width: CGFloat,
        height: CGFloat,
        spacing: CGFloat,
        vertical: Bool,
        edge: NoteEdge,
        flipHorizontal: Bool = false
    ) -> CGImage? {
        let scale = UIScreen.main.scale
        let pixelWidth = max(1, Int((width * scale).rounded()))
        let pixelHeight = max(1, Int((height * scale).rounded()))
        let pixelSpacing = max(1, Int((spacing * scale).rounded()))
        let key = "\(denom.id)|\(pixelWidth)|\(pixelHeight)|\(pixelSpacing)|\(vertical)|\(edge.rawValue)" as NSString
        if let cached = Self.sideImages.object(forKey: key) {
            return cached.cgImage
        }

        let size = CGSize(width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            let rect = CGRect(origin: .zero, size: size)

            // The banknote's own edge, pixel for pixel, stretched across the
            // cuboid face. No averaged color and no painted-on substitute.
            if let strip = edgeStripImage(denom: denom, edge: edge) {
                cg.interpolationQuality = .high
                if flipHorizontal {
                    cg.saveGState()
                    cg.translateBy(x: size.width, y: 0)
                    cg.scaleBy(x: -1, y: 1)
                    cg.draw(strip, in: rect)
                    cg.restoreGState()
                } else {
                    cg.draw(strip, in: rect)
                }
            } else {
                cg.setFillColor(UIColor(hex: denom.sideColor).cgColor)
                cg.fill(rect)
            }

            let colors = [
                UIColor.white.withAlphaComponent(0.10).cgColor,
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.10).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1]) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }

            // A thin line per note. Cap the count so a tall pile does not
            // spend its time drawing hundreds of nearly invisible hairlines.
            let step = CGFloat(pixelSpacing) / scale
            let length = vertical ? size.height : size.width
            let rawCount = Int(ceil(length / max(step, 0.5)))
            let lineCount = min(96, max(1, rawCount))
            let lineStep = length / CGFloat(lineCount)
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.16).cgColor)
            cg.setLineWidth(max(0.4, 0.6 / scale))
            if vertical {
                var x: CGFloat = 0
                for _ in 0...lineCount {
                    cg.move(to: CGPoint(x: x, y: 0))
                    cg.addLine(to: CGPoint(x: x, y: size.height))
                    x += lineStep
                }
            } else {
                var y: CGFloat = 0
                for _ in 0...lineCount {
                    cg.move(to: CGPoint(x: 0, y: y))
                    cg.addLine(to: CGPoint(x: size.width, y: y))
                    y += lineStep
                }
            }
            cg.strokePath()
        }
        Self.sideImages.setObject(image, forKey: key)
        return image.cgImage
    }

    private func edgeStripImage(denom: Denomination, edge: NoteEdge) -> CGImage? {
        let key = "\(denom.id)|\(edge.rawValue)" as NSString
        if let cached = Self.edgeStrips.object(forKey: key) {
            return cached.cgImage
        }
        guard let image = noteImage(denom.imageName)?.cgImage else { return nil }
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let shortSide = min(width, height)
        let inset = max(1, (shortSide * 0.004).rounded())
        let band = max(2, (shortSide * 0.012).rounded())
        let rect: CGRect
        let outputSize: CGSize
        switch edge {
        case .left:
            rect = CGRect(x: inset, y: 0, width: band, height: height)
            outputSize = CGSize(width: 1, height: height)
        case .right:
            rect = CGRect(x: max(0, width - inset - band), y: 0, width: band, height: height)
            outputSize = CGSize(width: 1, height: height)
        case .top:
            rect = CGRect(x: 0, y: inset, width: width, height: band)
            outputSize = CGSize(width: width, height: 1)
        case .bottom:
            rect = CGRect(x: 0, y: max(0, height - inset - band), width: width, height: band)
            outputSize = CGSize(width: width, height: 1)
        }
        guard let bandImage = image.cropping(to: rect.integral) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let stripImage = renderer.image { context in
            context.cgContext.interpolationQuality = .high
            context.cgContext.draw(
                bandImage,
                in: CGRect(origin: .zero, size: outputSize)
            )
        }
        guard let strip = stripImage.cgImage else { return nil }
        Self.edgeStrips.setObject(UIImage(cgImage: strip, scale: 1, orientation: .up), forKey: key)
        return strip
    }

    private static let noteImages = NSCache<NSString, UIImage>()
    private static let edgeStrips = NSCache<NSString, UIImage>()
    private static let sideImages = NSCache<NSString, UIImage>()
    private static let boxImages = NSCache<NSString, UIImage>()

    private static let shadowImage: CGImage? = {
        let size = CGSize(width: 128, height: 96)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            let colors = [
                UIColor.black.withAlphaComponent(0.62).cgColor,
                UIColor.black.withAlphaComponent(0.28).cgColor,
                UIColor.clear.cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                cg.drawRadialGradient(
                    gradient,
                    startCenter: center,
                    startRadius: 0,
                    endCenter: center,
                    endRadius: size.width / 2,
                    options: []
                )
            }
        }
        return image.cgImage
    }()

    private static let noActions: [String: CAAction] = [
        "bounds": NSNull(),
        "position": NSNull(),
        "transform": NSNull(),
        "contents": NSNull(),
        "opacity": NSNull(),
        "backgroundColor": NSNull(),
        "borderWidth": NSNull()
    ]

    // MARK: - 3D math

    private func worldTransform(x: CGFloat, y: CGFloat) -> CATransform3D {
        let rotation = multiply(rotationZ(yaw * .pi / 180), rotationX(pitch * .pi / 180))
        // Loose piles keep their bottom note on z = 0 and grow upward. Move
        // the pile down by its projected height centroid so the stack, not
        // the bottom note, is what the viewer sees centered.
        let lift = pileHeightCentroid * CGFloat(sin(pitch * .pi / 180))
        return multiply(rotation, translation(x, y + lift, 0))
    }

    private static func heightCentroid(of items: [CashItemSpec]) -> CGFloat {
        var weighted: CGFloat = 0
        var volume: CGFloat = 0
        for item in items {
            for layer in item.layers {
                let cubic = max(0, layer.width * layer.depth * layer.thickness)
                weighted += cubic * (layer.z + layer.thickness / 2)
                volume += cubic
            }
        }
        return volume > 0 ? weighted / volume : 0
    }

    private func translation(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D {
        var t = CATransform3DIdentity
        t.m41 = x
        t.m42 = y
        t.m43 = z
        return t
    }

    private func rotationX(_ angle: CGFloat) -> CATransform3D {
        var t = CATransform3DIdentity
        let c = cos(angle)
        let s = sin(angle)
        t.m22 = c
        t.m23 = s
        t.m32 = -s
        t.m33 = c
        return t
    }

    private func rotationY(_ angle: CGFloat) -> CATransform3D {
        var t = CATransform3DIdentity
        let c = cos(angle)
        let s = sin(angle)
        t.m11 = c
        t.m13 = -s
        t.m31 = s
        t.m33 = c
        return t
    }

    private func rotationZ(_ angle: CGFloat) -> CATransform3D {
        var t = CATransform3DIdentity
        let c = cos(angle)
        let s = sin(angle)
        t.m11 = c
        t.m12 = s
        t.m21 = -s
        t.m22 = c
        return t
    }

    private func multiply(_ a: CATransform3D, _ b: CATransform3D) -> CATransform3D {
        let av = values(of: a)
        let bv = values(of: b)
        var result = [CGFloat](repeating: 0, count: 16)
        for row in 0..<4 {
            for column in 0..<4 {
                var sum: CGFloat = 0
                for k in 0..<4 {
                    sum += av[row * 4 + k] * bv[k * 4 + column]
                }
                result[row * 4 + column] = sum
            }
        }
        return matrix(from: result)
    }

    private func values(of transform: CATransform3D) -> [CGFloat] {
        var copy = transform
        return withUnsafePointer(to: &copy) { pointer in
            pointer.withMemoryRebound(to: CGFloat.self, capacity: 16) { rebound in
                Array(UnsafeBufferPointer(start: rebound, count: 16))
            }
        }
    }

    private func matrix(from values: [CGFloat]) -> CATransform3D {
        var t = CATransform3DIdentity
        t.m11 = values[0]
        t.m12 = values[1]
        t.m13 = values[2]
        t.m14 = values[3]
        t.m21 = values[4]
        t.m22 = values[5]
        t.m23 = values[6]
        t.m24 = values[7]
        t.m31 = values[8]
        t.m32 = values[9]
        t.m33 = values[10]
        t.m34 = values[11]
        t.m41 = values[12]
        t.m42 = values[13]
        t.m43 = values[14]
        t.m44 = values[15]
        return t
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
