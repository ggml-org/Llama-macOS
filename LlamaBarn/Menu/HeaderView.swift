import AppKit
import Foundation

/// Header row showing app name and server status.
final class HeaderView: ItemView {

  private unowned let server: LlamaServer
  private let appNameLabel = Theme.primaryLabel()
  private let statusStackView = NSStackView()
  private let statusLabel = Theme.secondaryLabel()
  private let linkLabel = Theme.secondaryLabel()
  private let copyImageView = NSImageView()
  private let webUiLabel = Theme.secondaryLabel()

  private var currentUrl: URL?
  private var webUiUrl: URL?
  private var showingCopyConfirmation = false

  init(server: LlamaServer) {
    self.server = server
    super.init(frame: .zero)
    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var highlightEnabled: Bool { false }

  private func setup() {
    widthAnchor.constraint(equalToConstant: Layout.menuWidth).isActive = true

    appNameLabel.stringValue = "LlamaBarn"

    // Status stack for horizontal layout of status elements
    statusStackView.translatesAutoresizingMaskIntoConstraints = false
    statusStackView.orientation = .horizontal
    statusStackView.spacing = 0
    statusStackView.alignment = .firstBaseline
    statusStackView.distribution = .fill

    // Main stack for vertical layout of app name and status
    let mainStack = NSStackView(views: [appNameLabel, statusStackView])
    mainStack.orientation = .vertical
    mainStack.alignment = .leading
    mainStack.spacing = Layout.textLineSpacing

    contentView.addSubview(mainStack)
    mainStack.pinToSuperview()

    // Link Label Configuration
    linkLabel.isSelectable = false  // Make it look like a label, not editable

    // Copy Image View Configuration
    copyImageView.image = NSImage(
      systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy URL")
    copyImageView.toolTip = "Copy URL"
    copyImageView.contentTintColor = Theme.Colors.textSecondary
    copyImageView.symbolConfiguration = .init(pointSize: 11, weight: .regular)
    copyImageView.setContentHuggingPriority(.init(251), for: .horizontal)

    let copyClick = NSClickGestureRecognizer(target: self, action: #selector(copyUrl))
    copyImageView.addGestureRecognizer(copyClick)

    // Web UI Label Configuration
    let webUiClick = NSClickGestureRecognizer(target: self, action: #selector(openWebUi))
    webUiLabel.addGestureRecognizer(webUiClick)
    webUiLabel.isSelectable = false

    statusStackView.addArrangedSubview(statusLabel)
    statusStackView.addArrangedSubview(linkLabel)

    // Spacer between URL and copy button
    let urlCopySpacer = NSView()
    urlCopySpacer.translatesAutoresizingMaskIntoConstraints = false
    urlCopySpacer.widthAnchor.constraint(equalToConstant: 4).isActive = true
    statusStackView.addArrangedSubview(urlCopySpacer)

    statusStackView.addArrangedSubview(copyImageView)

    // Spacer between Copy and Web UI
    let copyWebUiSpacer = NSView()
    copyWebUiSpacer.translatesAutoresizingMaskIntoConstraints = false
    copyWebUiSpacer.widthAnchor.constraint(equalToConstant: 8).isActive = true
    statusStackView.addArrangedSubview(copyWebUiSpacer)

    // Flexible spacer to right-align Web UI
    let webUiSpacer = NSView()
    webUiSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
    statusStackView.addArrangedSubview(webUiSpacer)

    statusStackView.addArrangedSubview(webUiLabel)
  }

  func refresh() {
    // Update server status based on server state.
    if server.isRunning {
      appNameLabel.stringValue = "LlamaBarn"

      let host =
        UserSettings.exposeToNetwork ? (LlamaServer.getLocalIpAddress() ?? "0.0.0.0") : "localhost"
      let linkText = "\(host):\(LlamaServer.defaultPort)"
      let apiUrlString = "http://\(linkText)/v1"
      let webUiUrlString = "http://\(linkText)/"

      self.currentUrl = URL(string: apiUrlString)!
      self.webUiUrl = URL(string: webUiUrlString)!

      statusLabel.stringValue = "Base URL: "
      statusLabel.textColor = Theme.Colors.textSecondary
      statusLabel.isHidden = false

      let displayString = apiUrlString.replacingOccurrences(of: "http://", with: "")
      let attrTitle = NSAttributedString(
        string: displayString,
        attributes: [
          .foregroundColor: Theme.Colors.textPrimary,
          .font: Theme.Fonts.secondary,
        ]
      )
      linkLabel.attributedStringValue = attrTitle
      linkLabel.isHidden = false
      copyImageView.isHidden = false
      webUiLabel.isHidden = false

      let attrWebUi = NSAttributedString(
        string: "Web UI",
        attributes: [
          .foregroundColor: NSColor.linkColor,
          .font: Theme.Fonts.secondary,
          .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
      )
      webUiLabel.attributedStringValue = attrWebUi

      // Update copy icon based on confirmation state
      let iconName = showingCopyConfirmation ? "checkmark" : "doc.on.doc"
      copyImageView.image = NSImage(
        systemSymbolName: iconName, accessibilityDescription: "Copy URL")
    } else {
      appNameLabel.stringValue = "LlamaBarn"
      statusLabel.stringValue = "Select a model to run"
      statusLabel.textColor = Theme.Colors.textPrimary
      statusLabel.isHidden = false
      linkLabel.isHidden = true
      webUiLabel.isHidden = true
      copyImageView.isHidden = true
      currentUrl = nil
      webUiUrl = nil
    }

    needsDisplay = true
  }

  @objc private func openWebUi() {
    if let url = webUiUrl {
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
