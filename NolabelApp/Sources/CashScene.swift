import CoreGraphics
import Foundation

enum CashItemKind {
    case box
    case bundle
    case stack
    case remainder
    case pile
}

struct CashLayerSpec {
    let denomination: Denomination
    let width: CGFloat
    let depth: CGFloat
    let thickness: CGFloat
    let z: CGFloat
    let noteStep: CGFloat
}

struct CashItemSpec {
    let kind: CashItemKind
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let depth: CGFloat
    let height: CGFloat
    let layers: [CashLayerSpec]
    let showBand: Bool
    let showSeal: Bool
}

struct CashSceneSpec {
    let id: String
    let items: [CashItemSpec]

    static let empty = CashSceneSpec(id: "empty", items: [])
}

enum CashSceneSource {
    case cents(Int)
    case groups([CashGroup])

    var key: String {
        switch self {
        case .cents(let cents):
            return "cents|\(cents)"
        case .groups(let groups):
            guard !groups.isEmpty else { return .empty }
            let id = "groups|\(mode)|\(sizeKey)|" + groups.map { "\($0.denomination.id)x\($0.count)" }.joined(separator: ",")
            switch mode {
            case 2:
                return CashSceneSpec(id: id, items: groupedItems(groups, size: size))
            case 3:
                return CashSceneSpec(id: id, items: [])
            default:
                return CashSceneSpec(id: id, items: pileItems(groups, size: size))
            }
        case .cents(let cents):
            let groups = CashBreakdown.groups(for: cents)
            guard !groups.isEmpty else { return .empty }
            let id = "\(cents)|\(mode)|\(sizeKey)"
            switch mode {
            case 2:
                return CashSceneSpec(id: id, items: groupedItems(groups, size: size))
            case 3:
                return CashSceneSpec(id: id, items: [])
            default:
                if cents >= 1_000_000 {
                    return CashSceneSpec(id: id, items: packageItems(cents, size: size))
                }
                return CashSceneSpec(id: id, items: pileItems(groups, size: size))
            }
        }
    }

    static func spec(cents: Int, mode: Int, size: CGSize) -> CashSceneSpec {
        spec(source: .cents(cents), mode: mode, size: size)
    }

    // MARK: - Level 1: packaged cash

    private struct PackageBreakdown {
        let boxes: Int
        let bundles: Int
        let stacks: Int
        let remainderCents: Int
    }

    private static func packageBreakdown(_ cents: Int) -> PackageBreakdown {
        let boxes = cents / 100_000_000
        var rest = cents % 100_000_000
        let bundles = rest / 10_000_000
        rest %= 10_000_000
        let stacks = rest / 1_000_000
        let remainder = rest % 1_000_000
        return PackageBreakdown(boxes: boxes, bundles: bundles, stacks: stacks, remainderCents: remainder)
    }

    private struct Row {
        let kind: CashItemKind
        let shown: Int
    }

    private struct Slot {
        let kind: CashItemKind
        let count: Int
    }

    private struct Entry {
        let slot: Slot
        let slotWidth: CGFloat
        let drawn: CGFloat
        let rowGap: CGFloat
        let height: CGFloat
        let above: CGFloat
    }

    private static func packageItems(_ cents: Int, size: CGSize) -> [CashItemSpec] {
        let breakdown = packageBreakdown(cents)
        var rows: [Row] = []
        if breakdown.boxes > 0 {
            rows.append(Row(kind: .box, shown: Swift.min(breakdown.boxes, packageVisibleLimit)))
        }
        if breakdown.bundles > 0 {
            rows.append(Row(kind: .bundle, shown: Swift.min(breakdown.bundles, packageVisibleLimit)))
        }
        if breakdown.stacks > 0 {
            rows.append(Row(kind: .stack, shown: Swift.min(breakdown.stacks, packageVisibleLimit)))
        }
        if breakdown.remainderCents > 0 {
            rows.append(Row(kind: .remainder, shown: 1))
        }
        guard !rows.isEmpty else { return [] }

        let width = size.width
        let height = size.height
        let availableWidth = width * 0.82
        let boxGap: CGFloat = 6
        let noteGap: CGFloat = 14
        let rowGapY: CGFloat = 6

        var splits = Array(repeating: 1, count: rows.count)
        var slotCount = rows.count
        for (index, row) in rows.enumerated() {
            if row.kind == .box, row.shown >= 3, slotCount < 4 {
                splits[index] = 2
                slotCount += 1
            }
            if row.kind == .stack, row.shown >= 4, slotCount < 4 {
                let parts = Swift.min(3, Swift.min(Int(ceil(Double(row.shown) / 2.0)), 4 - slotCount + 1))
                if parts > 1 {
                    splits[index] = parts
                    slotCount += parts - 1
                }
            }
        }

        var slots: [Slot] = []
        for (index, row) in rows.enumerated() {
            let parts = splits[index]
            let base = row.shown / parts
            let extra = row.shown % parts
            for part in 0..<parts {
                let count = base + (part < extra ? 1 : 0)
                if count > 0 {
                    slots.append(Slot(kind: row.kind, count: count))
                }
            }
        }

        let factor: CGFloat = slotCount >= 4 ? 0.65 : (slotCount == 3 ? 0.80 : 1)
        let boxBaseWidth = Swift.min(width * 0.84, height * 0.88) * factor
        let noteMaxWidth = Swift.min(width * 0.60, 224)
        let hasNotes = slots.contains { $0.kind != .box }

        func heightRatio(_ kind: CashItemKind) -> CGFloat {
            switch kind {
            case .box: 1.03
            case .bundle: 1.275
            case .stack: 0.774
            case .remainder: 0.615
            case .pile: 0.774
            }
        }

        func aboveRatio(_ kind: CashItemKind) -> CGFloat {
            switch kind {
            case .box: 0.72
            case .bundle: 0.734
            case .stack: 0.523
            case .remainder: 0.511
            case .pile: 0.523
            }
        }

        func gap(for kind: CashItemKind) -> CGFloat {
            kind == .box ? boxGap : noteGap
        }

        func slotCap(_ slot: Slot) -> CGFloat {
            let gap = gap(for: slot.kind)
            return (availableWidth - gap * CGFloat(slot.count - 1)) / CGFloat(slot.count)
        }

        func layout(at noteWidth: CGFloat) -> (entries: [Entry], total: CGFloat) {
            let noteSlots = slots.filter { $0.kind != .box }
            let boxSlots = slots.filter { $0.kind == .box }
            var noteCap = noteMaxWidth
            for slot in noteSlots {
                noteCap = Swift.min(noteCap, slotCap(slot))
            }
            let noteBase = hasNotes ? Swift.min(noteWidth, noteCap) : 0

            var boxSlotWidth: CGFloat = 0
            if !boxSlots.isEmpty {
                var cap = hasNotes ? noteBase * 1.25 / packageBoxDrawScale : boxBaseWidth
                for slot in boxSlots {
                    cap = Swift.min(cap, slotCap(slot))
                }
                boxSlotWidth = cap
            }
            let boxDrawn = boxSlotWidth * packageBoxDrawScale

            var entries: [Entry] = []
            for slot in slots {
                if slot.kind == .box {
                    entries.append(Entry(
                        slot: slot,
                        slotWidth: boxSlotWidth,
                        drawn: boxDrawn,
                        rowGap: boxGap,
                        height: boxDrawn * heightRatio(.box),
                        above: aboveRatio(.box)
                    ))
                } else {
                    entries.append(Entry(
                        slot: slot,
                        slotWidth: noteBase,
                        drawn: noteBase,
                        rowGap: noteGap,
                        height: noteBase * heightRatio(slot.kind),
                        above: aboveRatio(slot.kind)
                    ))
                }
            }

            let total = entries.reduce(0) { $0 + $1.height } + rowGapY * CGFloat(Swift.max(0, entries.count - 1))
            return (entries, total)
        }

        var noteWidth = noteMaxWidth
        var result = layout(at: noteWidth)
        if result.total > height - 20 {
            var low: CGFloat = 0
            var high = noteMaxWidth
            for _ in 0..<20 {
                let mid = (low + high) / 2
                if layout(at: mid).total > height - 20 {
                    high = mid
                } else {
                    low = mid
                }
            }
            noteWidth = low
            result = layout(at: noteWidth)
        }

        var cursor = (height - result.total) / 2
        if result.entries.count == 1 {
            cursor = Swift.max(4, cursor - height * 0.05)
        }

        var items: [CashItemSpec] = []
        for entry in result.entries {
            let baseY = cursor + entry.height * entry.above
            let totalWidth = entry.slotWidth * CGFloat(entry.slot.count)
                + entry.rowGap * CGFloat(entry.slot.count - 1)
            let firstX = width / 2 - totalWidth / 2 + entry.slotWidth / 2
            for index in 0..<entry.slot.count {
                let x = firstX + CGFloat(index) * (entry.slotWidth + entry.rowGap)
                switch entry.slot.kind {
                case .box:
                    items.append(boxItem(x: x, y: baseY, width: entry.drawn))
                case .bundle:
                    items.append(notePackage(x: x, y: baseY, width: entry.drawn, kind: .bundle))
                case .stack:
                    items.append(notePackage(x: x, y: baseY, width: entry.drawn, kind: .stack))
                case .remainder:
                    if let item = remainderItem(x: x, y: baseY, width: entry.drawn, cents: breakdown.remainderCents) {
                        items.append(item)
                    }
                case .pile:
                    break
                }
            }
            cursor += entry.height + rowGapY
        }
        return items
    }

    private static func boxItem(x: CGFloat, y: CGFloat, width: CGFloat) -> CashItemSpec {
        CashItemSpec(
            kind: .box,
            x: x,
            y: y,
            width: width,
            depth: width * 0.62,
            height: width * 0.55,
            layers: [],
            showBand: false,
            showSeal: false
        )
    }

    private static func notePackage(x: CGFloat, y: CGFloat, width: CGFloat, kind: CashItemKind) -> CashItemSpec {
        let denom = Denomination.all[0]
        let depth = width / denom.ratio
        let notes: CGFloat = kind == .bundle ? 1000 : 100
        let height = notes * width * noteThicknessMM / denom.physicalWidth
        let layer = CashLayerSpec(
            denomination: denom,
            width: width,
            depth: depth,
            thickness: height,
            z: 0,
            noteStep: Swift.max(1.2, width * noteThicknessMM / denom.physicalWidth)
        )
        return CashItemSpec(
            kind: kind,
            x: x,
            y: y,
            width: width,
            depth: depth,
            height: height,
            layers: [layer],
            showBand: true,
            showSeal: kind == .bundle
        )
    }

    private static func remainderItem(x: CGFloat, y: CGFloat, width: CGFloat, cents: Int) -> CashItemSpec? {
        let groups = CashBreakdown.groups(for: cents)
        guard let first = groups.first else { return nil }
        let scale = width / first.denomination.baseWidth
        let perNote = width * noteThicknessMM / first.denomination.physicalWidth
        var layers: [CashLayerSpec] = []
        var z: CGFloat = 0
        for group in groups {
            let layerWidth = group.denomination.baseWidth * scale
            let depth = group.denomination.baseDepth * scale
            let thickness = Swift.max(0.8, CGFloat(group.count) * perNote)
            layers.append(CashLayerSpec(
                denomination: group.denomination,
                width: layerWidth,
                depth: depth,
                thickness: thickness,
                z: z,
                noteStep: Swift.max(0.01, perNote)
            ))
            z += thickness
        }
        return CashItemSpec(
            kind: .remainder,
            x: x,
            y: y,
            width: first.denomination.baseWidth * scale,
            depth: first.denomination.baseDepth * scale,
            height: z,
            layers: layers,
            showBand: false,
            showSeal: false
        )
    }

    // MARK: - Level 1: loose piles

    private static func pileItems(_ groups: [CashGroup], size: CGSize) -> [CashItemSpec] {
        let count = CashBreakdown.totalNotes(groups)
        guard count > 0 else { return [] }
        let width = size.width
        let height = size.height
        let maxThickness = Swift.max(58, height * 0.40)
        let maxNoteWidth = Swift.min(width * 0.60, 224)
        let layout = fitPiles(
            count: count,
            availableWidth: width * 0.92,
            maxNoteWidth: maxNoteWidth,
            maxThickness: maxThickness,
            physicalWidth: groups[0].denomination.physicalWidth
        )
        let targetWidth = layout.width
        let scale = targetWidth / groups[0].denomination.baseWidth
        let perNote = targetWidth * noteThicknessMM / groups[0].denomination.physicalWidth
        let piles = splitGroups(groups, into: layout.piles)
        let anchorHeight = targetWidth * 0.774
        let anchorCursor = Swift.max(4, (height - anchorHeight) / 2 - height * 0.05)
        let stackTop = anchorCursor + anchorHeight * 0.523

        var items: [CashItemSpec] = []
        for (index, pileGroups) in piles.enumerated() where !pileGroups.isEmpty {
            let x = width / 2 + (CGFloat(index) - CGFloat(layout.piles - 1) / 2) * (targetWidth + layout.gap)
            var layers: [CashLayerSpec] = []
            var z: CGFloat = 0
            for group in pileGroups {
                let layerWidth = group.denomination.baseWidth * scale
                let depth = group.denomination.baseDepth * scale
                let thickness = Swift.max(0.8, CGFloat(group.count) * perNote)
                layers.append(CashLayerSpec(
                    denomination: group.denomination,
                    width: layerWidth,
                    depth: depth,
                    thickness: thickness,
                    z: z,
                    noteStep: Swift.max(0.01, perNote)
                ))
                z += thickness
            }
            guard let first = pileGroups.first else { continue }
            items.append(CashItemSpec(
                kind: .pile,
                x: x,
                y: stackTop,
                width: first.denomination.baseWidth * scale,
                depth: first.denomination.baseDepth * scale,
                height: z,
                layers: layers,
                showBand: false,
                showSeal: false
            ))
        }
        return items
    }

    private struct PileLayout {
        let piles: Int
        let width: CGFloat
        let gap: CGFloat
    }

    private static func fitPiles(
        count: Int,
        availableWidth: CGFloat,
        maxNoteWidth: CGFloat,
        maxThickness: CGFloat,
        physicalWidth: CGFloat
    ) -> PileLayout {
        let gap: CGFloat = 3
        var best: PileLayout?
        for piles in 1...10 {
            let perPile = Int(ceil(Double(count) / Double(piles)))
            if perPile <= 0 { break }
            let widthByRow = (availableWidth - gap * CGFloat(piles - 1)) / CGFloat(piles)
            let widthByHeight = maxThickness * physicalWidth / (CGFloat(perPile) * noteThicknessMM)
            let width = Swift.min(maxNoteWidth, widthByRow, widthByHeight)
            if width < 6 { continue }
            if best == nil || width > best!.width + 0.01 {
                best = PileLayout(piles: piles, width: width, gap: gap)
            }
        }
        if let best {
            return best
        }
        let piles = Swift.max(1, Swift.min(10, count))
        let width = Swift.max(2, Swift.min(maxNoteWidth, (availableWidth - gap * CGFloat(piles - 1)) / CGFloat(piles)))
        return PileLayout(piles: piles, width: width, gap: gap)
    }

    private static func splitGroups(_ groups: [CashGroup], into piles: Int) -> [[CashGroup]] {
        guard piles > 0 else { return [] }
        var maps = Array(repeating: [String: Int](), count: piles)
        var cursor = 0
        for group in groups {
            for _ in 0..<group.count {
                let pile = cursor % piles
                maps[pile][group.denomination.id, default: 0] += 1
                cursor += 1
            }
        }
        return maps.map { map in
            Denomination.all.compactMap { denom in
                guard let count = map[denom.id], count > 0 else { return nil }
                return CashGroup(denomination: denom, count: count)
            }
        }
    }

    // MARK: - Level 2: grouped by denomination

    private static func groupedItems(_ groups: [CashGroup], size: CGSize) -> [CashItemSpec] {
        let width = size.width
        let height = size.height
        let columns = groups.count <= 3 ? groups.count : (groups.count == 4 ? 2 : 3)
        guard columns > 0 else { return [] }
        let rows = Int(ceil(Double(groups.count) / Double(columns)))
        let padX: CGFloat = 10
        let gapX: CGFloat = 6
        let cellWidth = (width - padX * 2 - gapX * CGFloat(columns - 1)) / CGFloat(columns)
        let rowBase: CGFloat = rows == 1 ? 0.56 : (rows == 2 ? 0.30 : 0.26)
        let rowGap: CGFloat = rows == 1 ? 0 : (rows == 2 ? 0.36 : 0.20)

        var items: [CashItemSpec] = []
        for (index, group) in groups.enumerated() {
            let row = index / columns
            let column = index % columns
            let rowCount = Swift.min(columns, groups.count - row * columns)
            let rowOffset = CGFloat(columns - rowCount) * (cellWidth + gapX) / 2
            let cellLeft = padX + rowOffset + CGFloat(column) * (cellWidth + gapX)
            let cellCenter = cellLeft + cellWidth / 2
            let baseY = height * (rowBase + CGFloat(row) * rowGap)

            let denom = group.denomination
            let noteWidth = Swift.min(cellWidth * 0.72, 92) * (denom.physicalWidth / 155)
            let scale = noteWidth / denom.baseWidth
            let depth = denom.baseDepth * scale
            let topPad = Swift.max(32, height * 0.10)
            let maxThickness = Swift.max(8, (baseY - topPad - depth * 0.58) / 0.90)
            let layout = fitPiles(
                count: group.count,
                availableWidth: cellWidth * 0.94,
                maxNoteWidth: noteWidth,
                maxThickness: maxThickness,
                physicalWidth: denom.physicalWidth
            )
            let perPile = Int(ceil(Double(group.count) / Double(layout.piles)))
            let perNote = layout.width * noteThicknessMM / denom.physicalWidth
            let step = CGFloat(perPile) * perNote > maxThickness
                ? Swift.max(0.01, maxThickness / CGFloat(perPile))
                : perNote
            let subWidth = layout.width
            let subDepth = denom.baseDepth * (subWidth / denom.baseWidth)

            for pile in 0..<layout.piles {
                let count = group.count / layout.piles + (pile < group.count % layout.piles ? 1 : 0)
                if count == 0 { continue }
                let thickness = Swift.max(0.8, CGFloat(count) * step)
                let x = cellCenter + (CGFloat(pile) - CGFloat(layout.piles - 1) / 2) * (subWidth + layout.gap)
                let layer = CashLayerSpec(
                    denomination: denom,
                    width: subWidth,
                    depth: subDepth,
                    thickness: thickness,
                    z: 0,
                    noteStep: Swift.max(0.01, step)
                )
                items.append(CashItemSpec(
                    kind: .pile,
                    x: x,
                    y: baseY,
                    width: subWidth,
                    depth: subDepth,
                    height: thickness,
                    layers: [layer],
                    showBand: false,
                    showSeal: false
                ))
            }
        }
        return items
    }
}
