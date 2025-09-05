import AppKit
import Foundation

/// Header row showing app name and versions.
final class HeaderMenuItemView: NSView {
  private enum Font {
    static let title = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let subtitle = NSFont.systemFont(ofSize: 10, weight: .regular)
  }
  private static let nf0: NumberFormatter = {
    let nf = NumberFormatter()
    nf.minimumFractionDigits = 0
    nf.maximumFractionDigits = 0
    return nf
  }()
  private static let nf1: NumberFormatter = {
    let nf = NumberFormatter()
    nf.minimumFractionDigits = 0
    nf.maximumFractionDigits = 1
    return nf
  }()

  private unowned let server: LlamaServer
  private let titleLabel = NSTextField(labelWithString: "")
  private let subtitleLabel = NSTextField(labelWithString: "")
  private let backgroundView = NSView()
  private let appBaseTitle = "LlamaBarn"
  private let versionString: String
  private let buildString: String
  private let llamaCppVersion: String

  init(server: LlamaServer, llamaCppVersion: String) {
    self.server = server
    // App version/build
    let ver =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    self.versionString = ver
    self.buildString = build
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
    subtitleLabel.stringValue = "\(versionString) · \(buildString) · \(llamaCppVersion)"

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
    // Always show a clean title; RAM usage now lives on the running model row.
    titleLabel.attributedStringValue = NSAttributedString(
      string: appBaseTitle,
      attributes: [
        .font: Font.title,
        .foregroundColor: NSColor.labelColor,
      ]
    )
    needsDisplay = true
  }
}
