import AppKit
import Foundation

/// Header row showing server status.
final class HeaderView: NSView {

  private unowned let server: LlamaServer
  private let stackView = NSStackView()
  private let statusLabel = Typography.makeSecondaryLabel()
  private let linkButton = NSButton()
  private let copyImageView = NSImageView()
  private let backgroundView = NSView()

  private var currentUrl: URL?
  private var showingCopyConfirmation = false

  init(server: LlamaServer) {
    self.server = server
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func setup() {
    wantsLayer = true
    backgroundView.wantsLayer = true

    widthAnchor.constraint(equalToConstant: Layout.menuWidth).isActive = true

    addSubview(backgroundView)
    backgroundView.addSubview(stackView)

    backgroundView.pinToSuperview(
      leading: Layout.outerHorizontalPadding,
      trailing: Layout.outerHorizontalPadding
    )

    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.pinToSuperview(
      top: 6,
      leading: Layout.innerHorizontalPadding,
      trailing: Layout.innerHorizontalPadding,
      bottom: 6
    )

    stackView.orientation = .horizontal
    stackView.spacing = 0
    stackView.alignment = .firstBaseline
    stackView.distribution = .fill

    // Link Button Configuration
    linkButton.isBordered = false
    linkButton.setButtonType(.momentaryChange)
    linkButton.imagePosition = .noImage
    linkButton.target = self
    linkButton.action = #selector(openLink)

    // Copy Image View Configuration
    copyImageView.image = NSImage(
      systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy URL")
    copyImageView.toolTip = "Copy URL"
    copyImageView.contentTintColor = Typography.secondaryColor
    copyImageView.symbolConfiguration = .init(pointSize: 11, weight: .regular)
    copyImageView.setContentHuggingPriority(.init(251), for: .horizontal)

    let copyClick = NSClickGestureRecognizer(target: self, action: #selector(copyUrl))
    copyImageView.addGestureRecognizer(copyClick)

    stackView.addArrangedSubview(statusLabel)
    stackView.addArrangedSubview(linkButton)
    stackView.addArrangedSubview(copyImageView)

    // Spacer
    let spacer = NSView()
    spacer.setContentHuggingPriority(.init(1), for: .horizontal)
    stackView.addArrangedSubview(spacer)
  }

  func refresh() {
    // Update server status based on server state.
    if server.isRunning {
      let host =
        UserSettings.exposeToNetwork ? (LlamaServer.getLocalIpAddress() ?? "0.0.0.0") : "localhost"
      let linkText = "\(host):\(LlamaServer.defaultPort)"
      let url = URL(string: "http://\(linkText)/")!

      self.currentUrl = url

      statusLabel.stringValue = "Running on "
      statusLabel.textColor = Typography.primaryColor

      let attrTitle = NSAttributedString(
        string: linkText,
        attributes: [
          .foregroundColor: NSColor.linkColor,
          .font: Typography.secondary,
          .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
      )
      linkButton.attributedTitle = attrTitle
      linkButton.isHidden = false
      copyImageView.isHidden = false

      // Update copy icon based on confirmation state
      let iconName = showingCopyConfirmation ? "checkmark" : "doc.on.doc"
      copyImageView.image = NSImage(
        systemSymbolName: iconName, accessibilityDescription: "Copy URL")
    } else {
      statusLabel.stringValue = "Select a model to run"
      statusLabel.textColor = Typography.primaryColor
      linkButton.isHidden = true
      linkButton.toolTip = nil
      copyImageView.isHidden = true
      currentUrl = nil
    }

    needsDisplay = true
  }

  @objc private func openLink() {
    if let url = currentUrl {
      NSWorkspace.shared.open(url)
    }
  }

  @objc private func copyUrl() {
    if let url = currentUrl {
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(url.absoluteString, forType: .string)

      // Show checkmark confirmation
      showingCopyConfirmation = true
      refresh()

      // Revert to copy icon after 1 second
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
        self?.showingCopyConfirmation = false
        self?.refresh()
      }
    }
  }

}
