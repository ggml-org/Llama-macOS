import AppKit
import Foundation

/// Header row showing app name and server status.
final class HeaderView: NSView {

  private unowned let server: LlamaServer
  private let appNameLabel = Typography.makePrimaryLabel()
  private let serverStatusLabel = Typography.makeSecondaryLabel()
  private let backgroundView = NSView()

  init(server: LlamaServer) {
    self.server = server
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

    appNameLabel.stringValue = "LlamaBarn"

    serverStatusLabel.allowsEditingTextAttributes = true
    serverStatusLabel.isSelectable = true

    let stack = NSStackView(views: [appNameLabel, serverStatusLabel])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 2
    stack.translatesAutoresizingMaskIntoConstraints = false

    addSubview(backgroundView)
    backgroundView.addSubview(stack)

    NSLayoutConstraint.activate([
      backgroundView.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: Layout.outerHorizontalPadding),
      backgroundView.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -Layout.outerHorizontalPadding),
      backgroundView.topAnchor.constraint(equalTo: topAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(
        equalTo: backgroundView.leadingAnchor, constant: Layout.innerHorizontalPadding),
      stack.trailingAnchor.constraint(
        equalTo: backgroundView.trailingAnchor, constant: -Layout.innerHorizontalPadding),
      stack.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 6),
      stack.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -6),
    ])
  }

  func refresh() {
    // Update server status based on server state.
    if server.isRunning {
      let linkText = "localhost:\(LlamaServer.defaultPort)"
      let modelName = server.activeModelName ?? "model"
      let full = "\(modelName) is running on \(linkText)"
      let url = URL(string: "http://\(linkText)/")!

      let attributed = NSMutableAttributedString(
        string: full,
        attributes: [
          .font: Typography.secondary,
          .foregroundColor: Typography.primaryColor,
        ]
      )
      // Color the model name with llamaGreen
      if let modelRange = full.range(of: modelName) {
        let nsRange = NSRange(modelRange, in: full)
        attributed.addAttribute(.foregroundColor, value: NSColor.llamaGreen, range: nsRange)
      }
      // Use .link attribute so NSTextField handles clicks automatically.
      if let range = full.range(of: linkText) {
        let nsRange = NSRange(range, in: full)
        attributed.addAttributes(
          [
            .link: url,
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
          ], range: nsRange)
      }
      serverStatusLabel.attributedStringValue = attributed
      serverStatusLabel.toolTip = "Open llama-server"
    } else {
      serverStatusLabel.attributedStringValue = NSAttributedString(
        string: "Select a model to run",
        attributes: [
          .font: Typography.secondary,
          .foregroundColor: Typography.secondaryColor,
        ]
      )
      serverStatusLabel.toolTip = nil
    }

    needsDisplay = true
  }

}
