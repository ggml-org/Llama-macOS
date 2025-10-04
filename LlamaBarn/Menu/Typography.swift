import AppKit

/// Shared type ramp for the app.
enum Typography {
  static let primary = NSFont.systemFont(ofSize: 13)
  // Secondary/line-2 text used across rows for consistency
  static let secondary = NSFont.systemFont(ofSize: 11, weight: .regular)

  /// Creates a label text field with primary font and proper menu text color.
  static func makePrimaryLabel(_ text: String = "") -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = primary
    label.textColor = .controlTextColor
    return label
  }

  /// Creates a label text field with secondary font and proper menu text color.
  static func makeSecondaryLabel(_ text: String = "") -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = secondary
    label.textColor = .controlTextColor
    return label
  }
}
