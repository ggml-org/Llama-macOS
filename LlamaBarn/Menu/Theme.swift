import AppKit

// Theme provides centralized styling for the app's UI
enum Theme {
  // Colors used throughout the app
  enum Colors {
    // Use custom color instead of NSColor.labelColor for better consistency with other macOS menus
    // labelColor's pure white in dark mode was too prominent
    static let textPrimary = NSColor.dynamic(
      light: NSColor.black.withAlphaComponent(0.85),
      dark: NSColor.white.withAlphaComponent(0.85)
    )
    // Tertiary text color -- used for less prominent text
    // Switched from NSColor.tertiaryLabelColor to custom dynamic color for predictability,
    // as semantic colors can have varying transparency across contexts, leading to contrast issues
    // (e.g., quantization labels becoming invisible on highlighted backgrounds).
    static let textSecondary = NSColor.dynamic(
      light: NSColor.black.withAlphaComponent(0.45),
      dark: NSColor.white.withAlphaComponent(0.45)
    )

    // Tint color for inactive model icons -- balanced between primary and secondary text
    static let modelIconTint = NSColor.dynamic(
      light: NSColor.black.withAlphaComponent(0.65),
      dark: NSColor.white.withAlphaComponent(0.65)
    )

    // Subtle background color for visual grouping -- adapts to light/dark mode
    static let subtleBackground = NSColor.dynamic(
      light: NSColor.black.withAlphaComponent(0.06),
      dark: NSColor.white.withAlphaComponent(0.11)
    )

    // Border color for separators and dividers -- adapts to light/dark mode
    static let border = NSColor.dynamic(
      light: NSColor.black.withAlphaComponent(0.15),
      dark: NSColor.white.withAlphaComponent(0.25)
    )

    // Separator color -- matches native separator visual weight
    static let separator = NSColor.dynamic(
      light: NSColor.black.withAlphaComponent(0.1),
      dark: NSColor.white.withAlphaComponent(0.15)
    )
  }

  // Fonts used throughout the app
  enum Fonts {
    // Primary font -- used for main text like model names
    static let primary = NSFont.systemFont(ofSize: 13)
    // Secondary font -- used for metadata and supplementary text
    static let secondary = NSFont.systemFont(ofSize: 11)
  }
}

// MARK: - Label Factories

// Factory methods for creating consistently styled text labels
extension Theme {
  // Creates a label with primary font (13pt) and primary text color
  // Used for main content like model names (line 1)
  static func primaryLabel(_ text: String = "") -> NSTextField {
    makeLabel(text, font: Fonts.primary, color: Colors.textPrimary)
  }

  // Creates a label with secondary font (11pt) and primary text color
  // Used for important metadata that should be smaller than primary text
  static func secondaryLabel(_ text: String = "") -> NSTextField {
    makeLabel(text, font: Fonts.secondary, color: Colors.textPrimary)
  }

  // Creates a label with secondary font (11pt) and tertiary text color
  // Used for less prominent metadata like model details (line 2)
  static func tertiaryLabel(_ text: String = "") -> NSTextField {
    makeLabel(text, font: Fonts.secondary, color: Colors.textSecondary)
  }

  // Internal helper -- creates a non-editable, non-selectable label with specified styling
  private static func makeLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = font
    label.textColor = color
    return label
  }
}

// MARK: - Attributed String Helpers

// Attribute dictionaries for creating styled NSAttributedString instances
extension Theme {
  // Returns attributes for primary-style text with custom color
  // Used when you need primary font but want control over the color
  static func primaryAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
    [.font: Fonts.primary, .foregroundColor: color]
  }

  // Returns attributes for secondary-style text with custom color
  // Used when you need secondary font but want control over the color
  static func secondaryAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
    [.font: Fonts.secondary, .foregroundColor: color]
  }

  // Attributes for tertiary-style text with fixed color
  // Used for de-emphasized metadata text
  static let tertiaryAttributes: [NSAttributedString.Key: Any] = [
    .font: Fonts.secondary,
    .foregroundColor: Colors.textSecondary,
  ]
}

// MARK: - Image View Configuration

// Helper for configuring image views with SF Symbols
extension Theme {
  // Configures an NSImageView with an SF Symbol icon and consistent styling
  // - Parameters:
  //   - view: The image view to configure
  //   - symbol: SF Symbol name (e.g., "circle.fill", "arrow.down")
  //   - tooltip: Optional hover tooltip text
  //   - color: Tint color for the symbol (defaults to textSecondary)
  //   - pointSize: Size of the symbol in points (defaults to 13)
  static func configure(
    _ view: NSImageView,
    symbol: String,
    tooltip: String? = nil,
    color: NSColor = Colors.textSecondary,
    pointSize: CGFloat = 13
  ) {
    view.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    view.toolTip = tooltip
    view.contentTintColor = color
    view.symbolConfiguration = .init(pointSize: pointSize, weight: .regular)
    view.translatesAutoresizingMaskIntoConstraints = false
  }

  // Configures an NSButton with an SF Symbol icon and consistent styling
  static func configure(
    _ button: NSButton,
    symbol: String,
    tooltip: String? = nil,
    color: NSColor = Colors.textSecondary,
    pointSize: CGFloat = 13
  ) {
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    button.toolTip = tooltip
    button.contentTintColor = color
    button.symbolConfiguration = .init(pointSize: pointSize, weight: .regular)
    button.isBordered = false
    button.title = ""
    button.bezelStyle = .inline
    button.translatesAutoresizingMaskIntoConstraints = false
  }
}

// MARK: - Helpers

// Creates colors that automatically adapt to light/dark mode
extension NSColor {
  // Creates a dynamic color that changes based on the system appearance
  // - Parameters:
  //   - light: Color to use in light mode
  //   - dark: Color to use in dark mode
  // - Returns: An NSColor that adapts to the current appearance
  static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    }
  }
}

// Helpers for setting CALayer colors that respect dynamic appearance
extension CALayer {
  // Sets the layer's background color, resolving dynamic colors for current appearance
  // - Parameters:
  //   - color: The color to set (can be dynamic)
  //   - view: The view whose appearance should be used for resolving the color
  func setBackgroundColor(_ color: NSColor, in view: NSView) {
    backgroundColor = color.resolvedColor(in: view)
  }

  // Sets the layer's border color, resolving dynamic colors for current appearance
  // - Parameters:
  //   - color: The color to set (can be dynamic)
  //   - view: The view whose appearance should be used for resolving the color
  func setBorderColor(_ color: NSColor, in view: NSView) {
    borderColor = color.resolvedColor(in: view)
  }
}

// Internal helper for resolving dynamic NSColor to CGColor
extension NSColor {
  // Resolves this NSColor to a CGColor using the view's effective appearance
  // This is needed because CALayer uses CGColor, not NSColor, and dynamic colors
  // need to be resolved in the context of a specific appearance
  // - Parameter view: The view whose effective appearance should be used
  // - Returns: A resolved CGColor appropriate for the current appearance
  fileprivate func resolvedColor(in view: NSView) -> CGColor {
    var resolved = NSColor.clear.cgColor
    view.effectiveAppearance.performAsCurrentDrawingAppearance {
      resolved = self.cgColor
    }
    return resolved
  }
}
