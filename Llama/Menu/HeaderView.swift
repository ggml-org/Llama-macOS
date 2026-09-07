import AppKit
import Foundation

/// Header: the app's name over the endpoint, its state, and the way into the
/// chat.
///
/// Two lines, in the shape every item below it uses -- identity on line one,
/// metadata on line two -- with the app as the subject and its address as the
/// metadata, so the top of the menu isn't a special case. The name is a title
/// and nothing else; it's also the only place the app is named in its own UI
/// (the footer carries versions, the menu bar carries a glyph).
///
/// Line one is the title and a state dot; line two is how the server is
/// reached, or -- when it can't be -- why.
///
/// The dot says the thing the menu otherwise never says: that there's a server
/// here and it's up, even with no model loaded. It also carries the states
/// that text can't. A restart resolves in well under a second (changing a
/// model's context length triggers one, so they're common), and a word that
/// appears and vanishes before it can be read costs attention without paying
/// anything back -- but a dot going grey for that same moment asks for no
/// reading, shifts no layout, and is free to be missed. It's how the menu
/// shows that a settings change restarts the server at all.
///
/// An error takes line two rather than crowding the title: that line is where
/// the endpoint lives, so when there isn't one, the reason belongs in its
/// place -- next to the retry that acts on it, with the room to say what
/// happened.
final class HeaderView: ItemView {

  private unowned let server: LlamaServer
  /// At the weight macOS gives the
  /// same thing: the system's own menu bar menus (Battery, Wi-Fi) title
  /// themselves in 13pt semibold over a secondary status line, with 13pt
  /// regular item names below. Measured off a Battery menu capture rather than
  /// guessed -- semibold matches its title's ink box exactly, medium doesn't.
  private let titleLabel = Theme.primaryLabel("Llama")
  private let statusDot = StatusDotView()
  /// Secondary (11pt) rather than primary: it shares the row with the chip and
  /// the chat link, and a 13pt word would set the row's height taller than the
  /// controls need.
  private let statusLabel = Theme.secondaryLabel()
  private let addressLabel = Theme.secondaryLabel()
  private let copyButton = NSButton()
  private let qrButton = NSButton()
  private let qrImageView = NSImageView()
  private let webUiLabel = Theme.secondaryLabel()
  private let restartLabel = Theme.secondaryLabel()

  private var currentUrl: URL?
  private var webUiUrl: URL?
  /// Whether the code is expanded under the address row.
  private var showingQRCode = false

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


    // A long bind error ("Port 9931 is in use by ...") can outrun the row; the
    // tooltip keeps the full text reachable.
    statusLabel.maximumNumberOfLines = 1
    statusLabel.lineBreakMode = .byTruncatingTail
    statusLabel.cell?.truncatesLastVisibleLine = true
    statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    // A plain glyph button rather than a control wrapping the whole address:
    // copying the URL is the rarest thing anyone does in this menu (a couple
    // of times per tool they wire up, then never), and a hover-highlighted run
    // of text would be an interaction pattern that exists nowhere else here --
    // not for the chat link, not for the code button, not in the footer.
    Theme.configure(copyButton, symbol: "doc.on.doc", tooltip: "Copy the base URL", pointSize: 10)
    copyButton.target = self
    copyButton.action = #selector(copyUrl)

    // Only useful once the server is bound off this machine, so `refresh()`
    // hides it for a localhost bind. It sits outside the chip: the chip's own
    // bounds group copying with the address, which keeps the code from reading
    // as a second thing to do with the same glyph.
    // 10pt like the copy glyph: at 11 its box stood taller than everything else
    // on the line, which read as the line reaching up toward the title.
    Theme.configure(qrButton, symbol: "qrcode", tooltip: "Show QR code", pointSize: 10)
    qrButton.target = self
    qrButton.action = #selector(showQRCode)
    qrButton.isHidden = true

    // The code sits under the address row and starts collapsed, so the menu
    // opens at its usual height and grows only when asked.
    qrImageView.isHidden = true
    // No smoothing: blurred module edges are what a camera fails on.
    qrImageView.imageScaling = .scaleNone
    NSLayoutConstraint.activate([
      qrImageView.widthAnchor.constraint(equalToConstant: QRCode.size),
      qrImageView.heightAnchor.constraint(equalToConstant: QRCode.size),
    ])

    // Spelled out rather than "WebUI": the person who came here to chat has no
    // reason to know that a web UI is a place rather than a setting.
    webUiLabel.attributedStringValue = NSAttributedString(
      string: "Open chat",
      attributes: Theme.secondaryAttributes(color: .linkColor)
    )
    webUiLabel.isSelectable = false
    webUiLabel.addGestureRecognizer(
      NSClickGestureRecognizer(target: self, action: #selector(openWebUi)))

    // Shown in place of the chat link when the server is in an error state, so
    // the user has a way to retry from the menu.
    restartLabel.attributedStringValue = NSAttributedString(
      string: "Retry",
      attributes: Theme.secondaryAttributes(color: .linkColor)
    )
    restartLabel.isSelectable = false
    restartLabel.isHidden = true
    restartLabel.addGestureRecognizer(
      NSClickGestureRecognizer(target: self, action: #selector(restartServer)))

    let actionRow = NSStackView(views: [
      addressLabel, copyButton, qrButton, statusLabel, NSView.flexibleSpacer(), webUiLabel,
      restartLabel,
    ])
    actionRow.orientation = .horizontal
    actionRow.alignment = .centerY
    actionRow.spacing = 6
    // The code button is a separate affordance, not a second thing to do with
    // the address, so it doesn't sit at the copy glyph's distance from it.
    actionRow.setCustomSpacing(10, after: copyButton)

    titleLabel.font = .systemFont(ofSize: Theme.Fonts.primary.pointSize, weight: .semibold)

    let titleRow = NSStackView(views: [titleLabel, statusDot])
    titleRow.orientation = .horizontal
    // Baselined rather than centered: the dot is placed against the title's
    // x-height (see StatusDotView), which centering on the row's box wouldn't
    // give it.
    titleRow.alignment = .firstBaseline
    titleRow.spacing = 6

    let mainStack = NSStackView(views: [titleRow, actionRow, qrImageView])
    mainStack.orientation = .vertical
    mainStack.alignment = .leading
    // The rows' own line spacing: the title and the address below it are two
    // lines of one block, not two stacked rows.
    mainStack.spacing = Layout.textLineSpacing
    // The glyphs on the address line stand taller than the text they sit with,
    // so the rows' text-to-text spacing leaves them crowding the title. Two
    // points back is what makes the gap read as even.
    mainStack.setCustomSpacing(Layout.textLineSpacing + 2, after: titleRow)
    // The code is a block rather than a line, so it needs the gap a block gets
    // or it reads as attached to the address above it.
    mainStack.setCustomSpacing(8, after: actionRow)

    contentView.addSubview(mainStack)
    mainStack.pinToSuperview()
  }

  func refresh() {
    // A hard server error (e.g. the port is held by another app) means there's
    // no working URL to show -- the error takes the status line, and the
    // address row collapses to the retry, since showing an endpoint would
    // imply the server is up.
    if case .error(let err) = server.state {
      let message = err.errorDescription ?? "Server error"
      setStatus(message, dot: .systemRed, tooltip: message)
      addressLabel.isHidden = true
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

    // Off-loopback: the address is now one another device can reach, which is
    // what makes the code worth offering.
    // Line two carries the endpoint, so it says nothing of its own here; the
    // dot has the state. Grey covers starting and restarting alike -- both are
    // moments on the way to running, and the address stays valid through them.
    switch server.state {
    case .running:
      setStatus(nil, dot: .systemGreen, tooltip: "Server running")
    case .idle, .loading:
      setStatus(nil, dot: Theme.Colors.textTertiary, tooltip: "Server restarting")
    case .error:
      break  // handled above
    }

    addressLabel.isHidden = false
    addressLabel.stringValue = linkText
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

    needsDisplay = true
  }

  /// Sets the dot (and its tooltip, so the colour isn't the only way to read
  /// it), plus line two's message -- `nil` whenever there's an endpoint to
  /// show there instead.
  private func setStatus(_ text: String?, dot color: NSColor, tooltip: String) {
    statusLabel.isHidden = text == nil
    statusLabel.stringValue = text ?? ""
    statusLabel.textColor = Theme.Colors.textPrimary
    statusLabel.toolTip = text
    statusDot.toolTip = tooltip
    statusDotColor = color
    statusDot.layer?.setBackgroundColor(color, in: self)
  }

  /// Kept so the dot can be re-resolved on a light/dark flip -- its layer holds
  /// a resolved CGColor, which doesn't follow the appearance on its own.
  private var statusDotColor: NSColor = .systemGreen

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    statusDot.layer?.setBackgroundColor(statusDotColor, in: self)
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
    guard let url = currentUrl else { return }
    Clipboard.copy(url.absoluteString)

    Theme.updateCopyIcon(copyButton, showingConfirmation: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self else { return }
      Theme.updateCopyIcon(self.copyButton, showingConfirmation: false)
    }
  }
}

// MARK: - Status dot

/// The 6pt state dot, with a baseline so it can sit in a baselined row of text.
///
/// Its baseline is placed to leave the dot centered on the x-height of the text
/// beside it -- sitting it *on* the baseline would hang it below the middle of
/// the word it follows.
private final class StatusDotView: NSView {

  private static let size: CGFloat = 6

  init() {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    layer?.cornerRadius = Self.size / 2
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: Self.size),
      heightAnchor.constraint(equalToConstant: Self.size),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// Half a point below the dot's bottom edge: the dot's centre then lands ~3.5pt
  /// above the baseline, which is about half the x-height of the 13pt title.
  override var firstBaselineOffsetFromTop: CGFloat { Self.size + 0.5 }
}

