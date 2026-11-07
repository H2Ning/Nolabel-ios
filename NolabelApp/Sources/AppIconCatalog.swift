import SwiftUI
import UIKit

/// The app currently exposes four icons in settings: panda (primary),
/// dog, rabbit and orange cat. The other icon assets remain in the bundle
/// for later, but are not shown in the picker.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case icon01 = "AppIcon-01"
    case icon02 = "AppIcon-02"
    case icon03 = "AppIcon-03"
    case icon04 = "AppIcon-04"
    case icon05 = "AppIcon-05"
    case icon06 = "AppIcon-06"
    case icon07 = "AppIcon-07"
    case icon08 = "AppIcon-08"
    case icon09 = "AppIcon-09"
    case icon10 = "AppIcon-10"
    case icon11 = "AppIcon-11"
    case icon12 = "AppIcon-12"
    case icon13 = "AppIcon-13"
    case icon14 = "AppIcon-14"
    case icon15 = "AppIcon-15"

    var id: String { rawValue }

    var assetName: String { rawValue }

    var previewName: String { "IconPreview-\(rawValue.suffix(2))" }

    var displayName: String {
        switch self {
        case .icon01: "橘猫"
        case .icon02: "黑猫"
        case .icon03: "灰猫"
        case .icon04: "奶牛猫"
        case .icon05: "奶茶猫"
        case .icon06: "蓝猫"
        case .icon07: "奶油猫"
        case .icon08: "粉猫"
        case .icon09: "薄荷猫"
        case .icon10: "紫猫"
        case .icon11: "熊猫"
        case .icon12: "小鸡"
        case .icon13: "小鸭"
        case .icon14: "小狗"
        case .icon15: "小兔"
        }
    }

    /// The primary icon is selected with `nil` rather than an asset name.
    var isPrimary: Bool { self == .icon11 }

    static let primary: AppIconChoice = .icon11

    /// Panda, dog, rabbit and orange cat.
    static let displayOrder: [AppIconChoice] = [
        .icon11, .icon14, .icon15, .icon01
    ]

    static var current: AppIconChoice {
        guard let name = UIApplication.shared.alternateIconName,
              let choice = AppIconChoice(rawValue: name),
              displayOrder.contains(choice) else { return .primary }
        return choice
    }

    /// True when no alternate icon is set, or the set icon is still in the picker.
    static var isCurrentIconAllowed: Bool {
        guard let name = UIApplication.shared.alternateIconName,
              let choice = AppIconChoice(rawValue: name) else { return true }
        return displayOrder.contains(choice)
    }
}
