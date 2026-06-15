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

  /// Formats a 0.0–1.0 fraction as a percentage string (e.g., "42%" or "42.5%").
  static func percentText(_ fraction: Double) -> String {
    let pct = max(0, min(100, fraction * 100))
    return formatDecimal(pct, unit: "%")
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

  /// Attributed subtitle for a downloading or paused row — e.g. "42% of 3.1 GB"
  /// or "42% of 3.1 GB · Paused". Uses the same secondary font as `modelMetadata`
  /// and the same no-tightening paragraph style so truncation behaves consistently.
  /// Replaces the usual "<size> ∣ <ctx>" metadata while a transfer is in flight;
  /// ctx tier is only meaningful for fully-downloaded models. When `fraction` is
  /// nil (paused with unknown total), falls back to just the size.
  static func downloadSubtitle(
    fraction: Double?, totalBytes: Int64, paused: Bool, color: NSColor
  ) -> NSAttributedString {
    let head =
      fraction.map { "\(percentText($0)) of \(gigabytes(totalBytes))" }
      ?? gigabytes(totalBytes)
    let text = paused ? "\(head) · Paused" : head
    return NSAttributedString(
      string: text,
      attributes: [
        .font: Theme.Fonts.secondary,
        .foregroundColor: color,
        .paragraphStyle: Theme.noTighteningParagraphStyle,
      ])
  }

  /// Formats model metadata text.
  /// Format: "3.1 GB  ∣  128k  ∣  4.2 GB mem" (file size + effective context
  /// tier + projected memory usage at that tier)
  /// If incompatibility is provided: "Requires a Mac with 32 GB+ of memory"
  /// For sideloaded models awaiting their MemProfile: "3.1 GB  ∣  estimating..."
  static func modelMetadata(
    for model: Model,
    color: NSColor = Theme.Colors.textPrimary,
    incompatibility: String? = nil
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()

    // Prevents letter spacing compression before truncation
    let paragraphStyle = Theme.noTighteningParagraphStyle

    let attributes: [NSAttributedString.Key: Any] = [
      .font: Theme.Fonts.secondary,
      .foregroundColor: color,
      .paragraphStyle: paragraphStyle,
    ]

    let secondaryAttributes: [NSAttributedString.Key: Any] = [
      .font: Theme.Fonts.secondary,
      .foregroundColor: Theme.Colors.textSecondary,
      .paragraphStyle: paragraphStyle,
    ]

    if let incompatibility = incompatibility {
      result.append(NSAttributedString(string: incompatibility, attributes: secondaryAttributes))
    } else {
      // File size
      result.append(NSAttributedString(string: model.totalSize, attributes: attributes))

      // Pipe separator
      result.append(NSAttributedString(string: "  ∣  ", attributes: secondaryAttributes))

      // Context tier or status for sideloaded models pending/failed MemProfile
      if model.ctxBytesPer1kTokens == 0 {
        result.append(NSAttributedString(string: "estimating...", attributes: secondaryAttributes))
      } else if model.ctxBytesPer1kTokens < 0 {
        result.append(NSAttributedString(string: "4k ctx", attributes: secondaryAttributes))
      } else if let tier = model.effectiveCtxTier {
        // When the device-fit tier is below the model's native max, show both:
        // "4k of 32k ctx" -- the fit value is the headline, the max is dimmed
        // context. When they match, just show the single tier label as before.
        if let nativeMax = model.nativeMaxTier, nativeMax > tier {
          result.append(NSAttributedString(string: tier.shortLabel, attributes: attributes))
          result.append(
            NSAttributedString(string: " of \(nativeMax.label)", attributes: secondaryAttributes))
        } else {
          result.append(NSAttributedString(string: tier.label, attributes: attributes))
        }

        // Projected memory usage at the selected tier (e.g. "3.3 GB mem") --
        // distinguishes runtime footprint from the on-disk size at the front.
        let ramMb = model.runtimeMemoryUsageMb(ctxWindowTokens: Double(tier.rawValue))
        result.append(NSAttributedString(string: "  ∣  ", attributes: secondaryAttributes))
        result.append(NSAttributedString(string: memory(mb: ramMb), attributes: attributes))
        result.append(NSAttributedString(string: " mem", attributes: secondaryAttributes))
      }
    }

    return result
  }

  /// Formats model name as "Family Size" with configurable colors.
  /// Prepends "org /" and appends tags after size.
  static func modelName(
    family: String,
    size: String,
    familyColor: NSColor,
    sizeColor: NSColor = Theme.Colors.textPrimary,
    hasVision: Bool = false,
    quantization: String? = nil,
    org: String,
    tags: [String] = []
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()

    // Org prefix in secondary color (e.g. "bartowski /") to disambiguate repos
    // that share a base name across orgs.
    result.append(
      NSAttributedString(
        string: "\(org) / ",
        attributes: Theme.primaryAttributes(color: Theme.Colors.textSecondary)))

    result.append(
      NSAttributedString(
        string: family, attributes: Theme.primaryAttributes(color: familyColor)))
    result.append(
      NSAttributedString(
        string: " \(size)", attributes: Theme.primaryAttributes(color: sizeColor)))

    // Tags after size in secondary color (e.g. "Instruct")
    if !tags.isEmpty {
      let tagStr = " " + tags.joined(separator: " ")
      result.append(
        NSAttributedString(
          string: tagStr,
          attributes: Theme.primaryAttributes(color: Theme.Colors.textSecondary)))
    }

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

    // Disable letter-spacing tightening before truncation (see Theme.noTighteningParagraphStyle).
    result.addAttribute(
      .paragraphStyle,
      value: Theme.noTighteningParagraphStyle,
      range: NSRange(location: 0, length: result.length))

    return result
  }
}
