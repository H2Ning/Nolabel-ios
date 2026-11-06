import SwiftUI
import UIKit

/// The fifteen alternate app icons. `AppIcon-11` (panda) is the primary icon;
/// the other fourteen are declared as alternate icon sets at build time.
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

    /// Panda, chick, duck, dog and rabbit first, then the ten cats.
    static let displayOrder: [AppIconChoice] = [
        .icon11, .icon12, .icon13, .icon14, .icon15,
        .icon01, .icon02, .icon03, .icon04, .icon05,
        .icon06, .icon07, .icon08, .icon09, .icon10
    ]

    static var current: AppIconChoice {
        guard let name = UIApplication.shared.alternateIconName,
              let choice = AppIconChoice(rawValue: name) else { return .primary }
        return choice
    }
}
