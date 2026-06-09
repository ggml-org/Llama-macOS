import AppKit
import Foundation

/// Header row showing app name and server status.
final class HeaderView: ItemView {

  private unowned let server: LlamaServer
  private let appNameLabel = Theme.primaryLabel()
  private let restartIcon = NSImageView()
  private let statusStackView = NSStackView()
  private let statusLabel = Theme.secondaryLabel()
  private let linkLabel = Theme.secondaryLabel()
  private let copyButton = NSButton()
  private let webUiLabel = Theme.secondaryLabel()

  private var currentUrl: URL?
  private var webUiUrl: URL?
  private var showingCopyConfirmation = false
  private var showingRestartIcon = false
  private var restartIconHideTask: DispatchWorkItem?

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

    // Restart icon -- shown briefly while server is restarting
    Theme.configure(restartIcon, symbol: "arrow.trianglehead.2.clockwise", pointSize: 11)
    restartIcon.contentTintColor = Theme.Colors.textSecondary
    restartIcon.isHidden = true

    // Title stack for horizontal layout of app name and restart icon
    let titleStack = NSStackView(views: [appNameLabel, restartIcon])
    titleStack.orientation = .horizontal
    titleStack.spacing = 6
    titleStack.alignment = .centerY

    // Status stack for horizontal layout of status elements
    statusStackView.translatesAutoresizingMaskIntoConstraints = false
    statusStackView.orientation = .horizontal
    statusStackView.spacing = 0
    statusStackView.alignment = .firstBaseline
    statusStackView.distribution = .fill

    // Main stack for vertical layout of title row and status
    let mainStack = NSStackView(views: [titleStack, statusStackView])
    mainStack.orientation = .vertical
    mainStack.alignment = .leading
    mainStack.spacing = Layout.textLineSpacing

    contentView.addSubview(mainStack)
    mainStack.pinToSuperview()

    // Link Label Configuration
    linkLabel.isSelectable = false  // Make it look like a label, not editable

    // Copy Button Configuration
    Theme.configure(copyButton, symbol: "doc.on.doc", tooltip: "Copy URL", pointSize: 11)
    copyButton.target = self
    copyButton.action = #selector(copyUrl)

    // WebUI Label Configuration
    let webUiClick = NSClickGestureRecognizer(target: self, action: #selector(openWebUi))
    webUiLabel.addGestureRecognizer(webUiClick)
    webUiLabel.isSelectable = false

    statusStackView.addArrangedSubview(statusLabel)
    statusStackView.addArrangedSubview(linkLabel)
    statusStackView.addArrangedSubview(NSView.spacer(width: 4))
    statusStackView.addArrangedSubview(copyButton)
    statusStackView.addArrangedSubview(NSView.spacer(width: 8))
    statusStackView.addArrangedSubview(NSView.flexibleSpacer())
    statusStackView.addArrangedSubview(webUiLabel)
  }

  func refresh() {
    // Show restart icon in debug builds only -- useful for development but
    // exposes implementation details that users don't need to see
    #if DEBUG
      if server.isLoading && !showingRestartIcon {
        showingRestartIcon = true
        restartIconHideTask?.cancel()
        restartIcon.isHidden = false
      } else if !server.isLoading && showingRestartIcon {
        // Delay hiding to ensure icon is visible for at least 250ms
        restartIconHideTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
          self?.showingRestartIcon = false
          self?.restartIcon.isHidden = true
        }
        restartIconHideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
      }
    #endif

    // Connect to server info
    appNameLabel.stringValue = "LlamaBarn"

    // Build server URLs using the resolved host (handles 0.0.0.0 -> local IP)
    let host = LlamaServer.resolvedHost
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
    copyButton.isHidden = false
    webUiLabel.isHidden = false

    let attrWebUi = NSAttributedString(
      string: "WebUI",
      attributes: [
        .foregroundColor: NSColor.linkColor,
        .font: Theme.Fonts.secondary,
      ]
    )
    webUiLabel.attributedStringValue = attrWebUi

    // Update copy icon based on confirmation state
    Theme.updateCopyIcon(copyButton, showingConfirmation: showingCopyConfirmation)

    needsDisplay = true
  }

  @objc private func openWebUi() {
    if let url = webUiUrl {
      NSWorkspace.shared.open(url)
    }
  }

  @objc private func copyUrl() {
    if let url = currentUrl {
      Clipboard.copy(url.absoluteString)

      // Show checkmark confirmation
      showingCopyConfirmation = true
      refresh()

      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
        self?.showingCopyConfirmation = false
        self?.refresh()
      }
    }
  }

}
