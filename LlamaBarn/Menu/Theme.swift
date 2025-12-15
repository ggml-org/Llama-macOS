import AppKit

enum Theme {
  enum Colors {
    static let textPrimary = NSColor.labelColor
    static let textSecondary = NSColor.tertiaryLabelColor

    static let subtleBackground = NSColor.dynamic(
      light: NSColor.black.withAlphaComponent(0.06),
      dark: NSColor.white.withAlphaComponent(0.11)
    )

    static let border = NSColor.dynamic(
      light: NSColor.black.withAlphaComponent(0.15),
      dark: NSColor.white.withAlphaComponent(0.25)
    )
  }

  enum Fonts {
    static let primary = NSFont.systemFont(ofSize: 13)
    static let secondary = NSFont.systemFont(ofSize: 11)
  }
}

// MARK: - Label Factories

extension Theme {
  static func primaryLabel(_ text: String = "") -> NSTextField {
    makeLabel(text, font: Fonts.primary, color: Colors.textPrimary)
  }

  static func secondaryLabel(_ text: String = "") -> NSTextField {
    makeLabel(text, font: Fonts.secondary, color: Colors.textPrimary)
  }

  static func tertiaryLabel(_ text: String = "") -> NSTextField {
    makeLabel(text, font: Fonts.secondary, color: Colors.textSecondary)
  }

  private static func makeLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = font
    label.textColor = color
    return label
  }
}

// MARK: - Attributed String Helpers

extension Theme {
  static func primaryAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
    [.font: Fonts.primary, .foregroundColor: color]
  }

  static func secondaryAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
    [.font: Fonts.secondary, .foregroundColor: color]
  }

  static let tertiaryAttributes: [NSAttributedString.Key: Any] = [
    .font: Fonts.secondary,
    .foregroundColor: Colors.textSecondary,
  ]
}

// MARK: - Image View Configuration

extension Theme {
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
}

// MARK: - Helpers

extension NSColor {
  static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    }
  }
}

extension CALayer {
  func setBackgroundColor(_ color: NSColor, in view: NSView) {
    backgroundColor = color.resolvedColor(in: view)
  }

  func setBorderColor(_ color: NSColor, in view: NSView) {
    borderColor = color.resolvedColor(in: view)
  }
}

extension NSColor {
  fileprivate func resolvedColor(in view: NSView) -> CGColor {
    var resolved = NSColor.clear.cgColor
    view.effectiveAppearance.performAsCurrentDrawingAppearance {
      resolved = self.cgColor
    }
    return resolved
  }
}
