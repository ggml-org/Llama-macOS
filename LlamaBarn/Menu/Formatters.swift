import AppKit
import Foundation

enum Format {
  // MARK: - Byte Formatting (decimal: 1 GB = 1e9 bytes)

  /// Formats bytes as decimal gigabytes with one fractional digit (e.g., "3.1 GB").
  /// Omits decimal point when fractional part is zero (e.g., "4 GB" not "4.0 GB").
  /// Uses 1 GB = 1,000,000,000 bytes to match network/download UI conventions.
  /// Uses period separator (US format) for consistency with memory formatting.
  static func gigabytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000.0
    return formatDecimal(gb, unit: " GB")
  }

  // MARK: - Token Formatting (binary: 1k = 1024)

  /// Formats token counts using binary units (1k = 1024).
  /// Examples: 131_072 → "128k", 262_144 → "256k", 32_768 → "32k", 4_096 → "4k"
  /// Omits decimal point when fractional part is zero (e.g., "4k" not "4.0k").
  /// Uses binary units since context lengths represent memory allocation.
  static func tokens(_ tokens: Int) -> String {
    if tokens >= 1_048_576 {
      return formatDecimal(Double(tokens) / 1_048_576.0, unit: "m")
    } else if tokens >= 10_240 {
      return String(format: "%.0fk", Double(tokens) / 1_024.0)
    } else if tokens >= 1_024 {
      return formatDecimal(Double(tokens) / 1_024.0, unit: "k")
    } else {
      return "\(tokens)"
    }
  }

  // MARK: - Memory Formatting (binary: 1 GB = 1024 MB)

  /// Formats binary megabytes as gigabytes with one decimal (e.g., "3.1 GB" from 3174 MB).
  /// Omits decimal point when fractional part is zero (e.g., "4 GB" not "4.0 GB").
  /// Uses binary units (1 GB = 1024 MB) to match Activity Monitor and system memory reporting.
  static func memory(mb: UInt64) -> String {
    let gb = Double(mb) / 1024.0
    return formatDecimal(gb, unit: " GB")
  }

  // MARK: - Quantization Formatting

  /// Extracts the first segment of a quantization label for compact display.
  /// Examples: "Q4_K_M" → "Q4", "Q8_0" → "Q8", "F16" → "F16"
  static func quantization(_ label: String) -> String {
    let upper = label.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !upper.isEmpty else { return upper }
    if let idx = upper.firstIndex(where: { $0 == "_" || $0 == "-" }) {
      let prefix = upper[..<idx]
      if !prefix.isEmpty { return String(prefix) }
    }
    return upper
  }

  // MARK: - Progress Formatting

  /// Formats progress percentage as a string (e.g., "42%" or "42.5%").
  static func progressText(_ progress: Progress) -> String {
    guard progress.totalUnitCount > 0 else { return "0%" }
    let fraction = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
    let percentage = max(0, min(100, fraction * 100))
    return formatDecimal(percentage, unit: "%")
  }

  // MARK: - Private Helpers

  /// Formats a value with one decimal place, omitting ".0" for whole numbers.
  private static func formatDecimal(_ value: Double, unit: String) -> String {
    let rounded = (value * 10).rounded() / 10
    let format = rounded.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f"
    return String(format: format, rounded) + unit
  }

  /// Creates an attributed string containing an SF Symbol with the specified color.
  private static func symbol(_ name: String, pointSize: CGFloat, color: NSColor)
    -> NSAttributedString
  {
    let attachment = NSTextAttachment()
    if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
      let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
      attachment.image = image.withSymbolConfiguration(config)
    }
    let result = NSMutableAttributedString(attachment: attachment)
    result.addAttribute(
      .foregroundColor, value: color, range: NSRange(location: 0, length: result.length))
    return result
  }
}

extension Format {
  // MARK: - Metadata Formatting

  /// Creates a bullet separator for metadata lines (e.g., "2.5 GB · 128k · 4 GB").
  /// Optionally accepts a paragraph style to prevent letter spacing compression.
  static func metadataSeparator(paragraphStyle: NSParagraphStyle? = nil) -> NSAttributedString {
    var attrs = Theme.tertiaryAttributes
    if let paragraphStyle {
      attrs[.paragraphStyle] = paragraphStyle
    }
    return NSAttributedString(string: " · ", attributes: attrs)
  }

  // MARK: - Model Metadata (composite)

  /// Formats model metadata text.
  /// Format: "3.1 GB  ∣  4k · 32k · 128k" (file size followed by supported context tiers)
  /// If incompatibility is provided: "Requires a Mac with 32 GB+ of memory"
  /// If loadedTier is provided, that tier label is shown in blue.
  static func modelMetadata(
    for model: CatalogEntry,
    color: NSColor = Theme.Colors.textPrimary,
    incompatibility: String? = nil,
    loadedTier: ContextTier? = nil
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()

    // Paragraph style that prevents letter spacing compression before truncation
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.allowsDefaultTighteningForTruncation = false

    let attributes: [NSAttributedString.Key: Any] = [
      .font: Theme.Fonts.secondary,
      .foregroundColor: color,
      .paragraphStyle: paragraphStyle,
    ]

    if let incompatibility = incompatibility {
      let warningAttr: [NSAttributedString.Key: Any] = [
        .font: Theme.Fonts.secondary,
        .foregroundColor: Theme.Colors.textSecondary,
        .paragraphStyle: paragraphStyle,
      ]
      result.append(NSAttributedString(string: incompatibility, attributes: warningAttr))
    } else {
      // File size
      result.append(NSAttributedString(string: model.totalSize, attributes: attributes))

      // Pipe separator between file size and context tiers
      result.append(
        NSAttributedString(
          string: "  ∣  ",
          attributes: [
            .font: Theme.Fonts.secondary,
            .foregroundColor: Theme.Colors.textSecondary,
            .paragraphStyle: paragraphStyle,
          ]))

      // Context Tiers - only show tiers this model supports on this device
      let supportedTiers = model.supportedContextTiers
      for (idx, tier) in supportedTiers.enumerated() {
        if idx > 0 {
          result.append(Format.metadataSeparator(paragraphStyle: paragraphStyle))
        }

        var tierAttributes = attributes
        if tier == loadedTier {
          // Running tier: show in blue to match the active model icon
          tierAttributes[.foregroundColor] = NSColor.controlAccentColor
        }

        result.append(NSAttributedString(string: tier.label, attributes: tierAttributes))
      }
    }

    return result
  }

  /// Formats family item text as "Family  ∣  Size · Size".
  static func familyItem(name: String, sizes: [(String, Bool)]) -> NSAttributedString {
    let result = NSMutableAttributedString()

    // Family name (more prominent)
    result.append(
      NSAttributedString(
        string: name,
        attributes: [
          .font: Theme.Fonts.secondary,
          .foregroundColor: Theme.Colors.textPrimary,
        ]))

    if !sizes.isEmpty {
      // Separator
      result.append(
        NSAttributedString(
          string: "  ∣  ",
          attributes: [
            .font: Theme.Fonts.secondary,
            .foregroundColor: Theme.Colors.textSecondary,
          ]))

      // Sizes list
      for (index, (size, isCompatible)) in sizes.enumerated() {
        if index > 0 {
          result.append(
            NSAttributedString(
              string: " · ",
              attributes: [
                .font: Theme.Fonts.secondary,
                .foregroundColor: Theme.Colors.textSecondary,
              ]))
        }

        let color = isCompatible ? Theme.Colors.modelIconTint : Theme.Colors.textSecondary
        result.append(
          NSAttributedString(
            string: size,
            attributes: [
              .font: Theme.Fonts.secondary,
              .foregroundColor: color,
            ]))
      }
    }

    return result
  }

  /// Formats model name as "Family Size" with configurable colors.
  /// Used by both installed and catalog model item views.
  static func modelName(
    family: String,
    size: String,
    familyColor: NSColor,
    sizeColor: NSColor = Theme.Colors.textPrimary,
    hasVision: Bool = false,
    quantization: String? = nil
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()
    result.append(
      NSAttributedString(
        string: family, attributes: Theme.primaryAttributes(color: familyColor)))
    result.append(
      NSAttributedString(
        string: " \(size)", attributes: Theme.primaryAttributes(color: sizeColor)))
    if hasVision {
      result.append(NSAttributedString(string: " "))
      result.append(
        Format.symbol(
          "eyeglasses", pointSize: Theme.Fonts.primary.pointSize, color: sizeColor))
    }
    if quantization != nil {
      result.append(NSAttributedString(string: " "))
      result.append(
        Format.symbol(
          "q.square", pointSize: Theme.Fonts.primary.pointSize, color: Theme.Colors.textSecondary))
    }
    return result
  }
}
