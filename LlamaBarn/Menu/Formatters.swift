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

  /// Calculates download progress percentage from a Progress object.
  /// Returns 0 if totalUnitCount is 0 or invalid, otherwise percentage 0-100.
  static func progress(_ progress: Progress) -> Int {
    guard progress.totalUnitCount > 0 else { return 0 }
    let fraction = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
    return max(0, min(100, Int(fraction * 100)))
  }

  /// Formats progress percentage as a string (e.g., "42%").
  static func progressText(_ progress: Progress) -> String {
    "\(Format.progress(progress))%"
  }

  // MARK: - Private Helpers

  /// Formats a value with one decimal place, omitting ".0" for whole numbers.
  private static func formatDecimal(_ value: Double, unit: String) -> String {
    let rounded = (value * 10).rounded() / 10
    let format = rounded.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f"
    return String(format: format + unit, rounded)
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
  static func metadataSeparator() -> NSAttributedString {
    NSAttributedString(string: " · ", attributes: Theme.tertiaryAttributes)
  }

  // MARK: - Model Metadata (composite)

  /// Formats model metadata text.
  /// Format: "2.53 GB" or "2.53 GB · 4.2 GB mem at 128k ctx · Q4 · 👓"
  /// (with memory usage shown when UserSettings.showEstimatedMemoryUsage is enabled,
  /// using the selected default context)
  static func modelMetadata(for model: CatalogEntry, color: NSColor = Theme.Colors.textPrimary)
    -> NSAttributedString
  {
    let result = NSMutableAttributedString()

    let attributes: [NSAttributedString.Key: Any] = [
      .font: Theme.Fonts.secondary,
      .foregroundColor: color,
    ]

    // Size on disk
    result.append(
      NSAttributedString(string: model.totalSize, attributes: attributes))

    // Quantization moved to model name

    // Calculate desired tokens and usable context
    let desiredTokens: Int
    if UserSettings.defaultContextWindow == .max {
      desiredTokens = 131_072
    } else {
      desiredTokens = UserSettings.defaultContextWindow.rawValue * 1024
    }

    let displayUsableCtx =
      model.usableCtxWindow(desiredTokens: desiredTokens, maximizeContext: false)
      ?? Int(CatalogEntry.compatibilityCtxWindowTokens)

    // Memory usage (optional)
    if UserSettings.showEstimatedMemoryUsage {
      result.append(Format.metadataSeparator())
      let memMb = model.runtimeMemoryUsageMb(ctxWindowTokens: Double(displayUsableCtx))
      let memString = Format.memory(mb: memMb)
      result.append(NSAttributedString(string: memString + " mem", attributes: attributes))
    }

    // Context info: displayed when the usable context is less than desired,
    // either due to memory constraints or the model's maximum context window.
    if displayUsableCtx != desiredTokens {
      result.append(Format.metadataSeparator())
      let ctxLabel = Format.tokens(displayUsableCtx)
      result.append(NSAttributedString(string: ctxLabel + " ctx", attributes: attributes))
    }

    // Vision support removed - now shown in model name

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
