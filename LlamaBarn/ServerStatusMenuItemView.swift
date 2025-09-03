import AppKit
import Foundation

/// AppKit menu row showing llama-server status.
/// Mirrors the prior SwiftUI ServerStatusView behavior.
final class ServerStatusMenuItemView: NSView {
  private enum Font {
    static let primary = NSFont.systemFont(ofSize: 13)
  }
  private unowned let server: LlamaServer
  private let onOpen: () -> Void

  private let iconView = NSImageView()
  private let textField = NSTextField(labelWithString: "")
  private let linkIcon = NSImageView()
  private let backgroundView = NSView()
  private var trackingArea: NSTrackingArea?
  private var isHighlighted = false { didSet { updateHighlight() } }

  init(server: LlamaServer, onOpen: @escaping () -> Void) {
    self.server = server
    self.onOpen = onOpen
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 260, height: 32) }

  private func setup() {
    wantsLayer = true
    backgroundView.translatesAutoresizingMaskIntoConstraints = false
    backgroundView.wantsLayer = true
    iconView.image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: nil)
    iconView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.contentTintColor = .secondaryLabelColor

    textField.font = Font.primary
    textField.lineBreakMode = .byTruncatingTail
    textField.translatesAutoresizingMaskIntoConstraints = false

    linkIcon.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
    linkIcon.symbolConfiguration = .init(pointSize: 12, weight: .regular)
    linkIcon.translatesAutoresizingMaskIntoConstraints = false
    linkIcon.contentTintColor = .secondaryLabelColor

    let spacer = NSView()
    spacer.translatesAutoresizingMaskIntoConstraints = false

    let stack = NSStackView(views: [iconView, textField, spacer, linkIcon])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 6
    addSubview(backgroundView)
    backgroundView.addSubview(stack)

    NSLayoutConstraint.activate([
      backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
      backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
      backgroundView.topAnchor.constraint(equalTo: topAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 18),
      iconView.heightAnchor.constraint(equalToConstant: 18),
      linkIcon.widthAnchor.constraint(equalToConstant: 14),
      linkIcon.heightAnchor.constraint(equalToConstant: 14),
      stack.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -8),
      stack.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 6),
      stack.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -6),
    ])
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
    trackingArea = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
    addTrackingArea(trackingArea!)
  }

  override func mouseEntered(with event: NSEvent) {
    guard server.isRunning else { return }
    isHighlighted = true
  }

  override func mouseExited(with event: NSEvent) { isHighlighted = false }

  override func mouseDown(with event: NSEvent) {
    guard server.isRunning else { return }
    onOpen()
  }

  private func updateHighlight() {
    if isHighlighted {
      backgroundView.layer?.backgroundColor = NSColor.cgColor(.lbHoverBackground, in: backgroundView)
    } else {
      backgroundView.layer?.backgroundColor = NSColor.clear.cgColor
    }
    backgroundView.layer?.cornerRadius = 6
  }

  func refresh() {
    if server.isRunning {
      textField.stringValue = "Running on localhost:\(LlamaServer.defaultPort)"
      textField.textColor = .labelColor
      iconView.contentTintColor = .labelColor
      linkIcon.contentTintColor = .linkColor
    } else {
      textField.stringValue = "Server not running"
      textField.textColor = .secondaryLabelColor
      iconView.contentTintColor = .secondaryLabelColor
      linkIcon.contentTintColor = .tertiaryLabelColor
      isHighlighted = false
    }
    needsDisplay = true
  }

}
