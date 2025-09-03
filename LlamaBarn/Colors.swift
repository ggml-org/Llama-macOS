import AppKit

// Central place for custom colors that are not satisfied by system semantic colors.
// Prefer semantic/dynamic colors so the UI adapts to light/dark automatically.
extension NSColor {
  private static func isDark(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
  }

  /// Greener, high-contrast variant for small status chips & indicators.
  static let llamaGreen: NSColor = NSColor(name: NSColor.Name("llamaGreen")) { appearance in
    if isDark(appearance) {
      // ~#65D679 (avoid neon; good contrast on dark bg)
      return NSColor(calibratedRed: 0.40, green: 0.84, blue: 0.47, alpha: 1.0)
    } else {
      // ~#1F7F3A (darker than systemGreen for tiny text)
      return NSColor(calibratedRed: 0.12, green: 0.50, blue: 0.23, alpha: 1.0)
    }
  }

  // MARK: - Semantic roles (text)
  // Prefer system semantic colors directly at call sites.

  /// Subtle border / hairline separator for pills & chips.
  /// Now mapped to system `separatorColor` for platform consistency.
  static let lbSubtleBorder: NSColor = .separatorColor

  /// Hover background for interactive rows.
  static let lbHoverBackground: NSColor = NSColor(name: NSColor.Name("lbHoverBackground")) { appearance in
    let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    let lightAlpha: CGFloat = increaseContrast ? 0.08 : 0.06  // black on light background
    let darkAlpha: CGFloat = increaseContrast ? 0.14 : 0.11  // white on dark background
    return isDark(appearance)
      ? NSColor.white.withAlphaComponent(darkAlpha)
      : NSColor.black.withAlphaComponent(lightAlpha)
  }

  /// Resolve a dynamic color to a `CGColor` for a specific view/appearance.
  /// Hides the `performAsCurrentDrawingAppearance` boilerplate used when assigning to CALayer properties.
  static func cgColor(_ color: NSColor, in view: NSView) -> CGColor {
    var result: CGColor = NSColor.clear.cgColor
    view.effectiveAppearance.performAsCurrentDrawingAppearance {
      result = color.cgColor
    }
    return result
  }
}
