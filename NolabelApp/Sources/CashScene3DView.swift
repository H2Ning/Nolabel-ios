import SwiftUI
import UIKit

struct CashScene3DView: UIViewRepresentable {
    let cents: Int
    let mode: Int
    let yaw: Double
    let pitch: Double
    let isDark: Bool

    func makeUIView(context: Context) -> CashSceneCanvas {
        let view = CashSceneCanvas()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: CashSceneCanvas, context: Context) {
        view.update(cents: cents, mode: mode, yaw: yaw, pitch: pitch, isDark: isDark)
    }
}

final class CashSceneCanvas: UIView {
    private let contentLayer = CALayer()
    private var nodes: [ItemNode] = []
    private var sceneKey = ""
    private var sceneSize: CGSize = .zero
    private var lastCents = 0
    private var lastMode = 1
    private var yaw: Double = Double(CashSceneLayout.defaultYaw)
    private var pitch: Double = Double(CashSceneLayout.packageTilt)

    private struct ItemNode {
        let layer: CALayer
        let x: CGFloat
        let y: CGFloat
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        layer.masksToBounds = true
        contentLayer.masksToBounds = true
        contentLayer.anchorPoint = .zero
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
        contentLayer.position = .zero
        if bounds.size != sceneSize {
            sceneSize = bounds.size
            rebuild(cents: lastCents, mode: lastMode)
        }
    }

    func update(cents: Int, mode: Int, yaw: Double, pitch: Double, isDark: Bool) {
        self.yaw = yaw
        self.pitch = pitch
        let nextKey = "\(cents)|\(mode)"
        if nextKey != sceneKey || bounds.size != sceneSize {
            sceneKey = nextKey
            lastCents = cents
            lastMode = mode
            rebuild(cents: cents, mode: mode)
        }
        updateTransforms()
    }

    private func rebuild(cents: Int, mode: Int) {
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

        let spec = CashSceneLayout.spec(cents: cents, mode: mode, size: size)
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
        let container = CALayer()
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
                    showSeal: item.showSeal,
                    isBundle: item.kind == .bundle
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
        showSeal: Bool,
        isBundle: Bool
    ) {
        let denom = spec.denomination
        let width = spec.width
        let depth = spec.depth
        let thickness = spec.thickness
        let zBottom = spec.z
        let zTop = zBottom + thickness
        let zCenter = zBottom + thickness / 2

        let shadowColor = UIColor(hex: denom.sideDarkColor)
        let side = sideImage(
            denom: denom,
            width: thickness,
            height: depth,
            spacing: spec.noteStep,
            vertical: true
        )
        let edge = sideImage(
            denom: denom,
            width: width,
            height: thickness,
            spacing: spec.noteStep,
            vertical: false
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
            image: side,
            width: thickness,
            height: depth,
            center: CGPoint(x: -width / 2, y: 0),
            z: zCenter,
            rotation: rotationY(-.pi / 2)
        )
        container.addSublayer(left)

        let right = sideFace(
            image: side,
            width: thickness,
            height: depth,
            center: CGPoint(x: width / 2, y: 0),
            z: zCenter,
            rotation: rotationY(.pi / 2)
        )
        container.addSublayer(right)

        let topSide = sideFace(
            image: edge,
            width: width,
            height: thickness,
            center: CGPoint(x: 0, y: -depth / 2),
            z: zCenter,
            rotation: rotationX(.pi / 2)
        )
        container.addSublayer(topSide)

        let bottomSide = sideFace(
            image: edge,
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
            addBand(to: face, width: width, depth: depth, isBundle: isBundle)
            addBandEdges(
                to: container,
                width: width,
                height: thickness,
                depth: depth,
                zCenter: zCenter,
                isBundle: isBundle
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

    private static let bandJitter: [CGFloat] = [
        0.500, 0.486, 0.512, 0.492, 0.505,
        0.479, 0.518, 0.494, 0.501, 0.489
    ]

    private func addBand(to face: CALayer, width: CGFloat, depth: CGFloat, isBundle: Bool) {
        let bandWidth = max(2, width * 0.10)
        let ratio = isBundle ? Self.bandJitter[Self.bandJitter.count - 1] : 0.5
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
        zCenter: CGFloat,
        isBundle: Bool
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

        if isBundle {
            let layerHeight = height / CGFloat(Self.bandJitter.count)
            for (index, ratio) in Self.bandJitter.enumerated() {
                addFrontBand(
                    to: front,
                    width: width,
                    bandWidth: bandWidth,
                    ratio: ratio,
                    y: (CGFloat(index) + 0.5) * layerHeight,
                    height: layerHeight
                )
                addFrontBand(
                    to: back,
                    width: width,
                    bandWidth: bandWidth,
                    ratio: ratio,
                    y: (CGFloat(index) + 0.5) * layerHeight,
                    height: layerHeight
                )
            }
        } else {
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
        let sealWidth = max(14, width * 0.36)
        let sealHeight = sealWidth * 314.0 / 640.0
        let seal = CALayer()
        seal.bounds = CGRect(x: 0, y: 0, width: sealWidth, height: sealHeight)
        seal.position = CGPoint(x: width * 0.5, y: depth * 0.5)
        seal.backgroundColor = UIColor(white: 0.985, alpha: 0.97).cgColor
        seal.cornerRadius = 1
        seal.borderWidth = 0.5
        seal.borderColor = UIColor(hex: 0xB2443A).withAlphaComponent(0.55).cgColor
        seal.zPosition = 0.5
        seal.actions = Self.noActions
        face.addSublayer(seal)

        let red = UIColor(hex: 0xB2443A)
        let bank = textLayer(
            "\u{4E2D}\u{56FD}\u{94F6}\u{884C}",
            size: max(3.2, sealWidth * 0.10),
            color: red,
            weight: .semibold
        )
        bank.frame = CGRect(x: 0, y: sealHeight * 0.10, width: sealWidth, height: sealHeight * 0.22)
        seal.addSublayer(bank)

        let amount = textLayer(
            "\u{58F9}\u{62FE}\u{4E07}\u{5143}\u{6574}",
            size: max(4.4, sealWidth * 0.16),
            color: red,
            weight: .bold
        )
        amount.frame = CGRect(x: 0, y: sealHeight * 0.40, width: sealWidth, height: sealHeight * 0.28)
        seal.addSublayer(amount)

        let foot = textLayer(
            "\u{5E74} \u{6708} \u{65E5}   \u{5C01}\u{7B7E}",
            size: max(2.6, sealWidth * 0.075),
            color: UIColor(hex: 0x6B5B4B),
            weight: .regular
        )
        foot.frame = CGRect(x: 0, y: sealHeight * 0.78, width: sealWidth, height: sealHeight * 0.16)
        seal.addSublayer(foot)
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
        front.transform = rotationX(-.pi / 2)
        front.isDoubleSided = false
        front.actions = Self.noActions
        container.addSublayer(front)

        let back = CALayer()
        back.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        back.position = CGPoint(x: 0, y: -depth / 2)
        back.zPosition = height / 2
        back.backgroundColor = backColor.cgColor
        back.transform = rotationX(.pi / 2)
        back.isDoubleSided = false
        back.actions = Self.noActions
        container.addSublayer(back)

        let left = CALayer()
        left.bounds = CGRect(x: 0, y: 0, width: height, height: depth)
        left.position = CGPoint(x: -width / 2, y: 0)
        left.zPosition = height / 2
        left.backgroundColor = sideColor.cgColor
        left.transform = rotationY(-.pi / 2)
        left.isDoubleSided = false
        left.actions = Self.noActions
        container.addSublayer(left)

        let right = CALayer()
        right.bounds = CGRect(x: 0, y: 0, width: height, height: depth)
        right.position = CGPoint(x: width / 2, y: 0)
        right.zPosition = height / 2
        right.backgroundColor = sideColor.cgColor
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
        top.addSublayer(topTape)

        for isRight in [false, true] {
            let sideTape = CALayer()
            sideTape.bounds = CGRect(x: 0, y: 0, width: max(2, height * 0.32), height: tapeWidth)
            sideTape.position = CGPoint(x: isRight ? height * 0.18 : height * 0.82, y: depth * 0.5)
            sideTape.backgroundColor = tape.withAlphaComponent(0.92).cgColor
            sideTape.zPosition = 0.2
            sideTape.actions = Self.noActions
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

    private func addGroundShadow(to container: CALayer, width: CGFloat, depth: CGFloat) {
        let shadow = CALayer()
        shadow.bounds = CGRect(x: 0, y: 0, width: max(20, width * 1.12), height: max(20, depth * 1.16))
        shadow.position = .zero
        shadow.zPosition = -1
        shadow.contents = Self.shadowImage
        shadow.contentsGravity = .resize
        shadow.opacity = 0.72
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
        vertical: Bool
    ) -> CGImage? {
        let scale = UIScreen.main.scale
        let pixelWidth = max(1, Int((width * scale).rounded()))
        let pixelHeight = max(1, Int((height * scale).rounded()))
        let pixelSpacing = max(1, Int((spacing * scale).rounded()))
        let key = "\(denom.id)|\(pixelWidth)|\(pixelHeight)|\(pixelSpacing)|\(vertical)" as NSString
        if let cached = Self.sideImages.object(forKey: key) {
            return cached.cgImage
        }

        let size = CGSize(width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale)
        let base = UIColor(hex: denom.sideColor)
        let line = UIColor(hex: denom.sideLineColor)
        let dark = UIColor(hex: denom.sideDarkColor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            let rect = CGRect(origin: .zero, size: size)
            cg.setFillColor(base.cgColor)
            cg.fill(rect)

            let colors = [
                UIColor.white.withAlphaComponent(0.16).cgColor,
                UIColor.clear.cgColor,
                dark.withAlphaComponent(0.18).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1]) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }

            cg.setStrokeColor(line.withAlphaComponent(0.58).cgColor)
            cg.setLineWidth(max(0.4, 0.6 / scale))
            if vertical {
                var x: CGFloat = 0
                while x <= size.width {
                    cg.move(to: CGPoint(x: x, y: 0))
                    cg.addLine(to: CGPoint(x: x, y: size.height))
                    x += CGFloat(pixelSpacing) / scale
                }
            } else {
                var y: CGFloat = 0
                while y <= size.height {
                    cg.move(to: CGPoint(x: 0, y: y))
                    cg.addLine(to: CGPoint(x: size.width, y: y))
                    y += CGFloat(pixelSpacing) / scale
                }
            }
            cg.strokePath()
        }
        Self.sideImages.setObject(image, forKey: key)
        return image.cgImage
    }

    private static let noteImages = NSCache<NSString, UIImage>()
    private static let sideImages = NSCache<NSString, UIImage>()

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
        let originX = sceneSize.width / 2
        let originY = sceneSize.height * 0.44

        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / CashSceneLayout.perspective

        let rotation = multiply(rotationZ(yaw * .pi / 180), rotationX(pitch * .pi / 180))
        let localToStage = multiply(rotation, translation(x, y, 0))
        let projection = multiply(
            multiply(translation(-originX, -originY, 0), perspective),
            translation(originX, originY, 0)
        )
        return multiply(localToStage, projection)
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
