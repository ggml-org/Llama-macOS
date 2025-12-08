import AppKit

// MARK: - Colors

extension NSColor {
  /// Subtle background for hover states and inactive icon containers.
  static let lbSubtleBackground = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor.white.withAlphaComponent(0.11)
      : NSColor.black.withAlphaComponent(0.06)
  }

  /// Border color for CALayers that don't support vibrancy.
  ///
  /// **Why not use `.separatorColor`?**
  /// System colors like `.separatorColor` rely on "Vibrancy" (blending with the blurred window background)
  /// to be visible. When converted to a `CGColor` for a `CALayer` border, this vibrancy effect is lost,
  /// leaving only the raw color value which is often too transparent (e.g., 10% opacity) to be seen.
  ///
  /// This color provides a "flat" opaque alternative that mimics the visual weight of a separator
  /// without relying on vibrancy effects.
  static let lbBorder = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor.white.withAlphaComponent(0.25)
      : NSColor.black.withAlphaComponent(0.15)
  }
}

// Helper for using dynamic NSColors with CALayer (which requires CGColor).
extension CALayer {
  func setBackgroundColor(_ color: NSColor, in view: NSView) {
    var resolved: CGColor = NSColor.clear.cgColor
    view.effectiveAppearance.performAsCurrentDrawingAppearance {
      resolved = color.cgColor
    }
    backgroundColor = resolved
  }

  func setBorderColor(_ color: NSColor, in view: NSView) {
    var resolved: CGColor = NSColor.clear.cgColor
    view.effectiveAppearance.performAsCurrentDrawingAppearance {
      resolved = color.cgColor
    }
    borderColor = resolved
  }
}

// MARK: - Typography

/// Shared type ramp and color system for the app.
enum Typography {
  // MARK: - Fonts
  static let primary = NSFont.systemFont(ofSize: 13)
  // Secondary/line-2 text used across rows for consistency
  static let secondary = NSFont.systemFont(ofSize: 11, weight: .regular)

  // MARK: - Colors
  static let primaryColor: NSColor = .secondaryLabelColor
  static let secondaryColor: NSColor = .tertiaryLabelColor

  // MARK: - Label Factories
  /// Creates a label text field with primary font and proper menu text color.
  static func makePrimaryLabel(_ text: String = "") -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = primary
    label.textColor = primaryColor
    return label
  }

  /// Creates a label text field with secondary font and proper menu text color.
  static func makeSecondaryLabel(_ text: String = "") -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = secondary
    label.textColor = primaryColor
    return label
  }

  /// Creates a label text field with secondary font and secondary menu text color.
  static func makeTertiaryLabel(_ text: String = "") -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = secondary
    label.textColor = secondaryColor
    return label
  }

  // MARK: - Attributed String Helpers
  /// Common attributes for secondary text (separators, dimmed text)
  static let tertiaryAttributes: [NSAttributedString.Key: Any] = [
    .font: secondary,
    .foregroundColor: secondaryColor,
  ]

  /// Creates attributes for primary font with custom color
  static func makePrimaryAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
    [.font: primary, .foregroundColor: color]
  }

  /// Creates attributes for secondary font with custom color
  static func makeSecondaryAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
    [.font: secondary, .foregroundColor: color]
  }
}
