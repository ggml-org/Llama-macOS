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
  private let qrButton = NSButton()
  private let qrImageView = NSImageView()
  private let webUiLabel = Theme.secondaryLabel()
  private let restartLabel = Theme.secondaryLabel()

  private var currentUrl: URL?
  private var webUiUrl: URL?
  /// Whether the code is expanded under the address row.
  private var showingQRCode = false
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

    appNameLabel.stringValue = "Llama"

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

    // The code sits under the status row and starts collapsed, so the menu
    // opens at its usual height and grows only when asked.
    qrImageView.isHidden = true
    // No smoothing: blurred module edges are what a camera fails on.
    qrImageView.imageScaling = .scaleNone
    NSLayoutConstraint.activate([
      qrImageView.widthAnchor.constraint(equalToConstant: QRCode.size),
      qrImageView.heightAnchor.constraint(equalToConstant: QRCode.size),
    ])

    // Main stack for vertical layout of title row and status
    let mainStack = NSStackView(views: [titleStack, statusStackView, qrImageView])
    mainStack.orientation = .vertical
    mainStack.alignment = .leading
    mainStack.spacing = Layout.textLineSpacing
    // The stack's spacing is meant for consecutive lines of text; the code is
    // a block rather than a line, so it needs the gap a block gets or it reads
    // as attached to the address above it.
    mainStack.setCustomSpacing(8, after: statusStackView)

    contentView.addSubview(mainStack)
    mainStack.pinToSuperview()

    // Link Label Configuration
    linkLabel.isSelectable = false  // Make it look like a label, not editable

    // Copy Button Configuration
    Theme.configure(copyButton, symbol: "doc.on.doc", tooltip: "Copy URL", pointSize: 11)
    copyButton.target = self
    copyButton.action = #selector(copyUrl)

    // QR Button Configuration -- only useful once the server is bound off this
    // machine, so `refresh()` hides it for a localhost bind.
    Theme.configure(qrButton, symbol: "qrcode", tooltip: "Show QR code", pointSize: 11)
    qrButton.target = self
    qrButton.action = #selector(showQRCode)
    qrButton.isHidden = true

    // WebUI Label Configuration
    let webUiClick = NSClickGestureRecognizer(target: self, action: #selector(openWebUi))
    webUiLabel.addGestureRecognizer(webUiClick)
    webUiLabel.isSelectable = false

    // Restart Label Configuration -- shown in place of the WebUI link when the
    // server is in an error state, so the user has a way to retry from the menu
    let restartClick = NSClickGestureRecognizer(target: self, action: #selector(restartServer))
    restartLabel.addGestureRecognizer(restartClick)
    restartLabel.isSelectable = false
    restartLabel.attributedStringValue = NSAttributedString(
      string: "Restart",
      attributes: [
        .foregroundColor: NSColor.linkColor,
        .font: Theme.Fonts.secondary,
      ]
    )
    restartLabel.isHidden = true

    statusStackView.addArrangedSubview(statusLabel)
    statusStackView.addArrangedSubview(linkLabel)
    statusStackView.addArrangedSubview(NSView.spacer(width: 4))
    statusStackView.addArrangedSubview(copyButton)
    statusStackView.addArrangedSubview(NSView.spacer(width: 4))
    statusStackView.addArrangedSubview(qrButton)
    statusStackView.addArrangedSubview(NSView.spacer(width: 8))
    statusStackView.addArrangedSubview(NSView.flexibleSpacer())
    statusStackView.addArrangedSubview(webUiLabel)
    statusStackView.addArrangedSubview(restartLabel)
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
    appNameLabel.stringValue = "Llama"

    // A hard server error (e.g. the port is held by another app) means there's
    // no working URL to show -- surface the reason in place of the Base URL /
    // WebUI row, which would otherwise misleadingly imply the server is up.
    if case .error(let err) = server.state {
      statusLabel.stringValue = err.errorDescription ?? "Server error"
      statusLabel.textColor = Theme.Colors.textSecondary
      statusLabel.isHidden = false
      linkLabel.isHidden = true
      copyButton.isHidden = true
      qrButton.isHidden = true
      showingQRCode = false
      qrImageView.isHidden = true
      webUiLabel.isHidden = true
      restartLabel.isHidden = false
      needsDisplay = true
      return
    }

    // Build server URLs using the resolved host (handles 0.0.0.0 -> local IP)
    let host = LlamaServer.resolvedHost
    let linkText = "\(host):\(LlamaServer.port)"
    // No `/v1` suffix: llama.cpp serves the OpenAI-compatible routes at the
    // root as well as under `/v1`, so the bare origin works both with clients
    // that append `/v1/...` themselves and with OpenAI SDKs that append
    // `/chat/completions` -- and it's the form tools like Pi expect.
    let apiUrlString = "http://\(linkText)"
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
    // A QR code for `localhost` would point the phone at itself.
    qrButton.isHidden = host == "localhost"
    // Collapse along with the button: an address that stopped being scannable
    // shouldn't leave a stale code open underneath it.
    if qrButton.isHidden { showingQRCode = false }

    qrImageView.isHidden = !showingQRCode
    if showingQRCode {
      let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      qrImageView.image = QRCode.image(
        for: webUiUrlString, size: QRCode.size, dark: dark,
        scale: window?.backingScaleFactor ?? 2)
    }
    webUiLabel.isHidden = false
    restartLabel.isHidden = true

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

  @objc private func restartServer() {
    // reload() regenerates models.ini first, so the retry also picks up any
    // config changes made since the crash; it runs from .error (only .idle skips).
    server.reload()
  }

  @objc private func openWebUi() {
    if let url = webUiUrl {
      openInBrowser(url)
    }
  }

  /// Expands or collapses the code in place.
  ///
  /// In place rather than in a popover: a popover can't appear over the menu's
  /// tracking loop, so presenting one meant closing the menu and opening a
  /// second panel where it had been -- which reads as the menu being replaced
  /// rather than as the row you clicked opening up.
  @objc private func showQRCode() {
    showingQRCode.toggle()
    refresh()

    // The menu sized itself when it opened, so growing the item's view isn't
    // enough on its own -- the menu has to be told its content changed.
    if let item = enclosingMenuItem {
      item.menu?.itemChanged(item)
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
