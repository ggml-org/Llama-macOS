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
/// It used to be more than a title, and that was the problem: it held line one
/// while nothing in the header said whether the server was up -- the address
/// below was printed identically whether the server was serving, still
/// starting, or wedged behind a taken port. State lives on line two now, in
/// the dot inside the chip, which frees the name to just be a name. The word
/// beside the chip appears only when it isn't the expected one: "Starting…"
/// while the server comes up, the bind error in place of the address when
/// there isn't a working one.
final class HeaderView: ItemView {

  private unowned let server: LlamaServer
  /// Set once -- a title with no second job, at the weight macOS gives the
  /// same thing: the system's own menu bar menus (Battery, Wi-Fi) title
  /// themselves in 13pt semibold over a secondary status line, with 13pt
  /// regular item names below. Measured off a Battery menu capture rather than
  /// guessed -- semibold matches its title's ink box exactly, medium doesn't.
  private let titleLabel = Theme.primaryLabel("Llama")
  private let statusDot = NSView()
  /// Secondary (11pt) rather than primary: it shares the row with the chip and
  /// the chat link, and a 13pt word would set the row's height taller than the
  /// controls need.
  private let statusLabel = Theme.secondaryLabel()
  private let urlChip = URLChipView()
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

    // Standalone dot -- shown only when the chip is hidden (the error state),
    // since the chip carries a dot of its own the rest of the time.
    statusDot.wantsLayer = true
    statusDot.layer?.cornerRadius = 3
    statusDot.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      statusDot.widthAnchor.constraint(equalToConstant: 6),
      statusDot.heightAnchor.constraint(equalToConstant: 6),
    ])

    // A long bind error ("Port 9931 is in use by ...") can outrun the row; the
    // tooltip keeps the full text reachable.
    statusLabel.maximumNumberOfLines = 1
    statusLabel.lineBreakMode = .byTruncatingTail
    statusLabel.cell?.truncatesLastVisibleLine = true
    statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    // The chip is the copy target: the address and the copy glyph are one
    // object, so there's no 13x13 icon to hit next to text that looks
    // copyable but isn't.
    urlChip.onClick = { [weak self] in self?.copyUrl() }

    // Only useful once the server is bound off this machine, so `refresh()`
    // hides it for a localhost bind. It sits outside the chip: the chip's own
    // bounds group copying with the address, which keeps the code from reading
    // as a second thing to do with the same glyph.
    Theme.configure(qrButton, symbol: "qrcode", tooltip: "Show QR code", pointSize: 11)
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
      statusDot, urlChip, qrButton, statusLabel, NSView.flexibleSpacer(), webUiLabel, restartLabel,
    ])
    actionRow.orientation = .horizontal
    actionRow.alignment = .centerY
    actionRow.spacing = 6
    // The code button is a separate affordance, not a second thing to do with
    // the address; at the row's 6pt spacing its glyph read as a pair with the
    // copy glyph just inside the chip's border.
    actionRow.setCustomSpacing(10, after: urlChip)

    titleLabel.font = .systemFont(ofSize: Theme.Fonts.primary.pointSize, weight: .semibold)

    let mainStack = NSStackView(views: [titleLabel, actionRow, qrImageView])
    mainStack.orientation = .vertical
    mainStack.alignment = .leading
    // The rows' own line spacing: the title and the address below it are two
    // lines of one block, not two stacked rows.
    mainStack.spacing = Layout.textLineSpacing
    // Except the chip isn't a line of text -- its box clears the text's cap
    // height by its own padding and border, so at the rows' 2pt its ink sits
    // closer to the title than a second text line's would. Giving that padding
    // back is what makes it *look* like the rows' spacing.
    mainStack.setCustomSpacing(Layout.textLineSpacing + 4, after: titleLabel)
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
      setStatus(message, dot: .systemOrange, color: Theme.Colors.textPrimary)
      statusDot.isHidden = false
      statusLabel.toolTip = message
      urlChip.isHidden = true
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
    let onNetwork = host != "localhost"
    switch server.state {
    case .running:
      // The expected state says nothing; the dot carries it. (Which also means
      // the row has no room to announce an off-loopback bind in words -- the
      // LAN address in the chip and the code button beside it are the tell.)
      setStatus(nil, dot: .systemGreen)
    case .idle, .loading:
      // The server is started at launch and stays up, so idle is a moment on
      // the way to running rather than a resting state of its own.
      setStatus("Starting…", dot: Theme.Colors.textTertiary)
    case .error:
      break  // handled above
    }

    urlChip.isHidden = false
    urlChip.address = linkText
    // The chip holds the dot whenever there's an address for it to sit beside.
    statusDot.isHidden = true
    // A QR code for `localhost` would point the phone at itself.
    qrButton.isHidden = !onNetwork
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

  /// Sets the dot, and the word beside it -- `nil` for the expected state,
  /// where the dot alone is the whole message.
  private func setStatus(
    _ text: String?, dot color: NSColor, color textColor: NSColor = Theme.Colors.textSecondary
  ) {
    statusLabel.isHidden = text == nil
    statusLabel.stringValue = text ?? ""
    statusLabel.textColor = textColor
    if text == nil { statusLabel.toolTip = nil }
    statusDotColor = color
    urlChip.dotColor = color
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

  private func copyUrl() {
    guard let url = currentUrl else { return }
    Clipboard.copy(url.absoluteString)

    urlChip.showingConfirmation = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.urlChip.showingConfirmation = false
    }
  }
}

// MARK: - URL chip

/// The endpoint as one object: the state dot, the address and a copy glyph
/// inside a single rounded control, so the whole thing is the button. Hover
/// fills it, a click copies and swaps the glyph for a checkmark.
///
/// The dot lives inside rather than beside: out in the row it read as floating
/// in the left margin rather than as belonging to the address it describes,
/// and it pushed the address off the column the rest of the menu starts on.
private final class URLChipView: NSView {

  var onClick: (() -> Void)?

  var address: String = "" {
    didSet { label.stringValue = address }
  }

  var dotColor: NSColor = .systemGreen {
    didSet { dot.layer?.setBackgroundColor(dotColor, in: self) }
  }

  var showingConfirmation = false {
    didSet {
      glyph.image = Theme.symbolImage(showingConfirmation ? "checkmark" : "doc.on.doc")
    }
  }

  private let label = Theme.secondaryLabel()
  private let glyph = NSImageView()
  private let dot = NSView()
  private var isHovered = false { didSet { restyle() } }
  private var trackingArea: NSTrackingArea?

  private static let cornerRadius: CGFloat = 5

  /// Both fills stay under the row-highlight weight: the chip is a control at
  /// rest, not a selected row.
  private static let restFill = NSColor.dynamic(
    light: NSColor.black.withAlphaComponent(0.05),
    dark: NSColor.white.withAlphaComponent(0.09)
  )
  private static let hoverFill = NSColor.dynamic(
    light: NSColor.black.withAlphaComponent(0.10),
    dark: NSColor.white.withAlphaComponent(0.16)
  )

  init() {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    layer?.cornerRadius = Self.cornerRadius
    layer?.borderWidth = 1

    toolTip = "Copy the base URL"

    Theme.configure(glyph, symbol: "doc.on.doc", pointSize: 10)

    // Same 6pt dot as the model page's title, so "running" reads the same way
    // wherever it's shown.
    dot.wantsLayer = true
    dot.layer?.cornerRadius = 3
    dot.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      dot.widthAnchor.constraint(equalToConstant: 6),
      dot.heightAnchor.constraint(equalToConstant: 6),
    ])

    let stack = NSStackView(views: [dot, label, glyph])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 5
    addSubview(stack)
    stack.pinToSuperview(top: 2, leading: 6, trailing: 6, bottom: 2)

    restyle()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func restyle() {
    layer?.setBackgroundColor(isHovered ? Self.hoverFill : Self.restFill, in: self)
    layer?.setBorderColor(Theme.Colors.separator, in: self)
    dot.layer?.setBackgroundColor(dotColor, in: self)
  }

  // The layer's colors are resolved CGColors; re-resolve on light/dark flips.
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self
    )
    addTrackingArea(area)
    trackingArea = area
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .pointingHand)
  }

  override func mouseEntered(with event: NSEvent) { isHovered = true }
  override func mouseExited(with event: NSEvent) { isHovered = false }
  override func mouseDown(with event: NSEvent) {}  // swallow, so the row behind stays put
  override func mouseUp(with event: NSEvent) { onClick?() }
}
