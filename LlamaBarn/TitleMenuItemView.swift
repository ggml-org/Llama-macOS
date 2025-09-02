import AppKit
import Foundation

/// Top menu title view showing app name, dynamic memory usage (when running), and a subtitle with version info.
final class TitleMenuItemView: NSView {
  private enum Font {
    static let title = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let subtitle = NSFont.systemFont(ofSize: 10, weight: .regular)
  }

  private unowned let server: LlamaServer
  private let titleLabel = NSTextField(labelWithString: "")
  private let subtitleLabel = NSTextField(labelWithString: "")
  private let backgroundView = NSView()
  private let appBaseTitle = "LlamaBarn"
  private let versionString: String
  private let llamaCppVersion: String

  init(server: LlamaServer, llamaCppVersion: String) {
    self.server = server
    // App version/build
    let ver =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    self.versionString = "v\(ver) (\(build))"
    self.llamaCppVersion = llamaCppVersion
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 260, height: 40) }

  private func setup() {
    wantsLayer = true
    backgroundView.translatesAutoresizingMaskIntoConstraints = false
    backgroundView.wantsLayer = true

    titleLabel.font = Font.title
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.lineBreakMode = .byTruncatingTail

    subtitleLabel.font = Font.subtitle
    subtitleLabel.textColor = .secondaryLabelColor
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
    subtitleLabel.lineBreakMode = .byTruncatingTail
    subtitleLabel.stringValue = "\(versionString) • llama.cpp \(llamaCppVersion)"

    let stack = NSStackView(views: [titleLabel, subtitleLabel])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 2
    stack.translatesAutoresizingMaskIntoConstraints = false

    addSubview(backgroundView)
    backgroundView.addSubview(stack)

    NSLayoutConstraint.activate([
      backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
      backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
      backgroundView.topAnchor.constraint(equalTo: topAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -8),
      stack.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 6),
      stack.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -6),
    ])
  }

  func refresh() {
    // Build dynamic title with optional memory usage
    if server.isRunning && server.memoryUsageMB > 0 {
      let memMB = server.memoryUsageMB
      let (value, unit): (Double, String) = memMB >= 1024 ? (memMB / 1024, "GB") : (memMB, "MB")
      let nf = NumberFormatter()
      nf.maximumFractionDigits = value < 10 && unit == "GB" ? 1 : 0
      nf.minimumFractionDigits = 0
      let valueStr = nf.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
      let full = appBaseTitle + "  •  " + valueStr + " " + unit
      let attr = NSMutableAttributedString(string: full)
      attr.addAttributes(
        [
          .font: Font.title,
          .foregroundColor: NSColor.labelColor,
        ], range: NSRange(location: 0, length: appBaseTitle.count))
      let memRange = NSRange(location: appBaseTitle.count, length: full.count - appBaseTitle.count)
      attr.addAttributes(
        [
          .font: NSFont.systemFont(ofSize: 11, weight: .regular),
          .foregroundColor: NSColor.secondaryLabelColor,
        ], range: memRange)
      titleLabel.attributedStringValue = attr
    } else {
      titleLabel.attributedStringValue = NSAttributedString(
        string: appBaseTitle,
        attributes: [
          .font: Font.title,
          .foregroundColor: NSColor.labelColor,
        ]
      )
    }
    needsDisplay = true
  }
}
