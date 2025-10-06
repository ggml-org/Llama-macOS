import AppKit

/// Helper for creating metadata labels with SF Symbol icons and text.
/// Colors are set explicitly: text uses secondaryLabelColor, separators use tertiaryLabelColor.
enum MetadataLabel {
  // MARK: - Symbols

  /// Creates a template SF Symbol with specified size and weight.
  /// Size defaults to 11pt to match Typography.secondary.
  /// Template images automatically adopt the text field's tint color.
  private static func makeSymbol(
    _ name: String, pointSize: CGFloat = 11, weight: NSFont.Weight = .regular
  ) -> NSImage? {
    guard
      let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
    else { return nil }
    image.isTemplate = true
    return image
  }

  // Metadata symbols (used with text)
  static let sizeSymbol = makeSymbol("internaldrive")
  static let contextSymbol = makeSymbol("text.word.spacing")
  static let memorySymbol = makeSymbol("memorychip")

  // Status symbols (used standalone)
  static let checkSymbol = makeSymbol("checkmark")

  // MARK: - Attributed String Builders

  /// Creates an attributed string containing only an icon (no text).
  /// Used for status indicators like checkmarks.
  static func makeIconOnly(icon: NSImage?) -> NSAttributedString {
    guard let icon else { return NSAttributedString() }
    return NSAttributedString(attachment: iconAttachment(for: icon))
  }

  /// Creates an attributed string with an icon followed by text (e.g., "📦 2.5 GB").
  /// If no icon provided, returns plain text with font and color applied.
  static func make(
    icon: NSImage?,
    text: String,
    font: NSFont = Typography.secondary
  ) -> NSAttributedString {
    guard let icon else {
      return NSAttributedString(string: text, attributes: Typography.secondaryAttributes)
    }

    let composed = NSMutableAttributedString(attachment: iconAttachment(for: icon))
    composed.append(
      NSAttributedString(string: " \(text)", attributes: Typography.secondaryAttributes))
    return composed
  }

  /// Creates a bullet separator for metadata lines (e.g., "2.5 GB • 128k • 4 GB").
  static func makeSeparator(font: NSFont = Typography.secondary) -> NSAttributedString {
    NSAttributedString(string: " • ", attributes: Typography.tertiaryAttributes)
  }

  // MARK: - Private Helpers

  /// Creates an NSTextAttachment for an icon.
  private static func iconAttachment(for icon: NSImage) -> NSTextAttachment {
    let attachment = NSTextAttachment()
    attachment.image = icon
    return attachment
  }
}
