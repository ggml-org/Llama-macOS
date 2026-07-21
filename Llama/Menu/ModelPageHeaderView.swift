import AppKit
import Foundation

/// Static identity and explicit actions at the top of a model page.
///
/// This is deliberately not a `ModelItemView`: a page header does not navigate
/// when clicked and should not inherit the list row's hover background or hidden
/// actions. The model's live loading state still appears in its icon.
final class ModelPageHeaderView: ItemView {
  private let model: Model
  private unowned let server: LlamaServer
  private let actionHandler: ModelActionHandler

  private let iconView = IconView()
  private let titleLabel = Theme.primaryLabel()
  private let chatButton = NSButton()
  private let copyIdButton = NSButton()
  private let destructiveButton = NSButton()

  init(
    model: Model,
    server: LlamaServer,
    actionHandler: ModelActionHandler,
    showTags: Bool
  ) {
    self.model = model
    self.server = server
    self.actionHandler = actionHandler
    super.init(frame: .zero)

    iconView.imageView.image =
      model.brandLogoAsset.flatMap { NSImage(named: $0) }
      ?? NSImage(systemSymbolName: "cube.fill", accessibilityDescription: "Model")

    titleLabel.attributedStringValue = Format.modelName(
      id: model.id,
      color: Theme.Colors.textPrimary,
      hasVision: model.hasVisionSupport,
      showTags: showTags
    )
    titleLabel.maximumNumberOfLines = 1
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.cell?.truncatesLastVisibleLine = true
    titleLabel.allowsDefaultTighteningForTruncation = false

    configureActionButton(
      chatButton, title: "Chat", symbol: "bubble.left", action: #selector(didClickChat))
    configureActionButton(
      copyIdButton, title: "Copy ID", symbol: "doc.on.doc", action: #selector(didClickCopyId))
    configureActionButton(
      destructiveButton, title: "Delete", symbol: "trash", action: #selector(didClickDestructive))

    setupLayout()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// A page header is static. Its individual buttons provide their own hover
  /// treatment, so highlighting the whole container would imply a dead click.
  override var highlightEnabled: Bool { false }

  private func configureActionButton(
    _ button: NSButton,
    title: String,
    symbol: String,
    action: Selector
  ) {
    button.title = title
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
    button.imagePosition = .imageLeading
    button.symbolConfiguration = .init(pointSize: 11, weight: .regular)
    button.controlSize = .small
    button.bezelStyle = .rounded
    button.font = Theme.Fonts.secondary
    button.target = self
    button.action = action
  }

  private func setupLayout() {
    let identityRow = NSStackView(views: [iconView, titleLabel])
    identityRow.orientation = .horizontal
    identityRow.alignment = .centerY
    identityRow.spacing = 6

    let actions = NSStackView(views: [chatButton, copyIdButton, destructiveButton])
    actions.orientation = .horizontal
    actions.alignment = .centerY
    actions.spacing = 6

    let stack = NSStackView(views: [identityRow, actions])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 6
    contentView.addSubview(stack)
    stack.pinToSuperview(top: 4, leading: 0, trailing: 0, bottom: 4)

    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: Layout.menuWidth),
      // The vertical stack's leading alignment otherwise lets a long identity
      // row keep its intrinsic width and widen the menu instead of truncating.
      identityRow.trailingAnchor.constraint(lessThanOrEqualTo: stack.trailingAnchor),
    ])
    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
  }

  /// Updates the status icon and changes the destructive page action between
  /// unloading a live model and deleting an idle one.
  func refresh() {
    let isActive = server.isActive(model: model)
    iconView.inactiveTintColor = Theme.Colors.modelIconTint
    iconView.setLoading(server.isLoading(model: model))
    iconView.isActive = isActive

    destructiveButton.title = isActive ? "Unload" : "Delete"
    destructiveButton.image = NSImage(
      systemSymbolName: isActive ? "eject" : "trash",
      accessibilityDescription: isActive ? "Unload" : "Delete")
  }

  private var chatUrl: URL? {
    var components = URLComponents()
    components.scheme = "http"
    components.host = LlamaServer.resolvedHost
    components.port = LlamaServer.port
    components.path = "/"
    components.queryItems = [URLQueryItem(name: "model", value: model.id)]
    return components.url
  }

  @objc private func didClickChat() {
    guard let url = chatUrl else { return }
    openInBrowser(url)
  }

  @objc private func didClickCopyId() {
    Clipboard.copy(model.id)
    Theme.updateCopyIcon(copyIdButton, showingConfirmation: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self else { return }
      Theme.updateCopyIcon(self.copyIdButton, showingConfirmation: false)
    }
  }

  @objc private func didClickDestructive() {
    if server.isActive(model: model) {
      actionHandler.performPrimaryAction(for: model)
    } else {
      actionHandler.delete(model: model)
    }
  }
}
