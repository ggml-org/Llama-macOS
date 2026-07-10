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

  /// Formats bytes picking the unit by magnitude: whole megabytes under 1 GB
  /// (e.g. "512 MB"), gigabytes with one decimal at/above (e.g. "1.2 GB"). Used
  /// for the live download readout so a small-but-growing figure ticks in MB and
  /// visibly moves, instead of sitting near "0.0 GB". Same decimal-unit
  /// convention as `gigabytes` (1 GB = 1e9 bytes).
  static func bytesAdaptive(_ bytes: Int64) -> String {
    if bytes < 1_000_000_000 {
      let mb = Double(bytes) / 1_000_000.0
      return String(format: "%.0f MB", mb)
    }
    return gigabytes(bytes)
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

  // MARK: - Private Helpers

  /// Formats a value with one decimal place, omitting ".0" for whole numbers.
  private static func formatDecimal(_ value: Double, unit: String) -> String {
    let rounded = (value * 10).rounded() / 10
    let format = rounded.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f"
    return String(format: format, rounded) + unit
  }

  /// Renders a metadata label (params, quant, tag) as a small pill chip
  /// (dimmed text on a subtle rounded background) attached inline after the
  /// model name. Drawn via an NSImage drawing handler, which runs at draw
  /// time, so the dynamic theme colors resolve against the current light/dark
  /// appearance.
  private static func chip(_ text: String) -> NSAttributedString {
    let font = NSFont.systemFont(ofSize: 9, weight: .medium)
    let textAttributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: Theme.Colors.textSecondary,
    ]
    let textSize = (text as NSString).size(withAttributes: textAttributes)
    let hPad: CGFloat = 5
    let chipSize = NSSize(width: ceil(textSize.width) + hPad * 2, height: 14)

    let image = NSImage(size: chipSize, flipped: false) { rect in
      let pill = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
      Theme.Colors.subtleBackground.setFill()
      pill.fill()
      (text as NSString).draw(
        at: NSPoint(x: hPad, y: (rect.height - textSize.height) / 2),
        withAttributes: textAttributes)
      return true
    }

    let attachment = NSTextAttachment()
    attachment.image = image
    // Nudge the chip down so it centers against the 13pt primary text's
    // x-height rather than sitting on the baseline.
    attachment.bounds = NSRect(x: 0, y: -2.5, width: chipSize.width, height: chipSize.height)
    return NSAttributedString(attachment: attachment)
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
  // MARK: - Model Metadata (composite)

  /// Transfer readout shown to the right of the progress bar while a download is
  /// in flight: "1.2 GB of 3.1 GB", with " · Paused" appended when interrupted.
  /// Progress is conveyed by the bar, so no percentage here. Uses tabular digits
  /// (so the counting-up "downloaded" figure doesn't jitter its width) and the same
  /// secondary font / color / no-tightening paragraph style as `modelMetadata`.
  static func downloadSubtitle(
    downloadedBytes: Int64, totalBytes: Int64, paused: Bool
  ) -> NSAttributedString {
    var text = "\(bytesAdaptive(downloadedBytes)) of \(bytesAdaptive(totalBytes))"
    if paused {
      text += " · Paused"
    }
    return NSAttributedString(
      string: text,
      attributes: [
        .font: Theme.Fonts.secondaryTabular,
        .foregroundColor: Theme.Colors.textSecondary,
        .paragraphStyle: Theme.noTighteningParagraphStyle,
      ])
  }

  /// Formats model metadata text.
  /// Format: "3.1 GB  ∣  4k ctx  ∣  4.2 GB mem" (file size + effective context
  /// tier + projected memory usage at that tier)
  /// If incompatibility is provided: "Requires a Mac with 32 GB+ of memory"
  /// For sideloaded models awaiting their MemProfile: "3.1 GB  ∣  estimating..."
  static func modelMetadata(
    for model: Model,
    incompatibility: String? = nil
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()

    // Prevents letter spacing compression before truncation
    let paragraphStyle = Theme.noTighteningParagraphStyle

    // The whole metadata line reads as secondary context, so values and units
    // share one dimmed color. Uses the proportional secondary font -- this line
    // is static, so it doesn't need the tabular digits the live download
    // subtitle relies on, and monospaced numbers look out of place here.
    let secondaryAttributes: [NSAttributedString.Key: Any] = [
      .font: Theme.Fonts.secondary,
      .foregroundColor: Theme.Colors.textSecondary,
      .paragraphStyle: paragraphStyle,
    ]

    if let incompatibility = incompatibility {
      result.append(NSAttributedString(string: incompatibility, attributes: secondaryAttributes))
    } else {
      // File size
      result.append(NSAttributedString(string: model.totalSize, attributes: secondaryAttributes))

      // Pipe separator
      result.append(NSAttributedString(string: "  ∣  ", attributes: secondaryAttributes))

      // Context tier or status for sideloaded models pending/failed MemProfile
      if model.ctxBytesPer1kTokens == 0 {
        result.append(NSAttributedString(string: "estimating...", attributes: secondaryAttributes))
      } else if model.ctxBytesPer1kTokens < 0 {
        result.append(NSAttributedString(string: "4k ctx", attributes: secondaryAttributes))
      } else if let tier = model.effectiveCtxTier {
        // Show only the device-fit tier (e.g. "4k ctx"). The model's native max
        // is available by expanding the row, so repeating it on every line here
        // is low-signal noise.
        result.append(NSAttributedString(string: tier.label, attributes: secondaryAttributes))

        // Projected memory usage at the selected tier (e.g. "3.3 GB mem") --
        // distinguishes runtime footprint from the on-disk size at the front.
        let ramMb = model.runtimeMemoryUsageMb(ctxWindowTokens: Double(tier.rawValue))
        result.append(NSAttributedString(string: "  ∣  ", attributes: secondaryAttributes))
        result.append(NSAttributedString(string: memory(mb: ramMb), attributes: secondaryAttributes))
        result.append(NSAttributedString(string: " mem", attributes: secondaryAttributes))
      }
    }

    return result
  }

  /// Formats a model's row title: the parsed view of its id
  /// (`ModelIdParser`), mirroring the WebUI's default rendering so the menu
  /// and the WebUI's picker agree. The short name renders as text; params,
  /// quant, and leftover repo segments render as small chips — metadata the
  /// eye can skip, while every chip still comes straight from the id. The
  /// raw id stays reachable via the row's tooltip (set by callers).
  static func modelName(
    id: String,
    color: NSColor,
    hasVision: Bool = false
  ) -> NSAttributedString {
    let parsed = ModelIdParser.parse(id)
    let result = NSMutableAttributedString()

    result.append(
      NSAttributedString(string: parsed.name, attributes: Theme.primaryAttributes(color: color)))

    // Chip order matches the WebUI: params, quant, then leftover tags.
    var chips: [String] = []
    if let params = parsed.params { chips.append(params) }
    if let quant = parsed.quant { chips.append(quant) }
    chips.append(contentsOf: parsed.tags)
    for text in chips {
      result.append(NSAttributedString(string: " "))
      result.append(chip(text))
    }

    if hasVision {
      result.append(NSAttributedString(string: " "))
      result.append(
        Format.symbol(
          "eyeglasses", pointSize: Theme.Fonts.primary.pointSize, color: color))
    }

    // Disable letter-spacing tightening before truncation (see Theme.noTighteningParagraphStyle).
    result.addAttribute(
      .paragraphStyle,
      value: Theme.noTighteningParagraphStyle,
      range: NSRange(location: 0, length: result.length))

    return result
  }
}
