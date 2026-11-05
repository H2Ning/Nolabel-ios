import SwiftUI
import UIKit

/// Fixed-size typography that still follows the user's Dynamic Type setting.
///
/// The app deliberately uses a tuned size scale, so instead of switching every
/// label to a system text style we scale the existing sizes through
/// `UIFontMetrics`, which tracks the current content size category.
///
/// `Text` gets its own overload so text-only modifiers such as `.tracking` and
/// `.monospacedDigit()` keep working after the font is applied.
extension Text {
    func scalableFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Text {
        font(.system(
            size: UIFontMetrics.default.scaledValue(for: size),
            weight: weight,
            design: design
        ))
    }
}

extension View {
    func scalableFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        font(.system(
            size: UIFontMetrics.default.scaledValue(for: size),
            weight: weight,
            design: design
        ))
    }
}
