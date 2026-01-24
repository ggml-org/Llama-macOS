import AppKit
import Foundation

final class ModelActionsView: ItemView {
  private let model: CatalogEntry
  private let actionHandler: ModelActionHandler

  private let finderButton = NSButton()
  private let hfButton = NSButton()
  private let deleteButton = NSButton()

  init(model: CatalogEntry, actionHandler: ModelActionHandler) {
    self.model = model
    self.actionHandler = actionHandler
    super.init(frame: .zero)
    setupLayout()
    configureViews()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: Layout.menuWidth, height: 32) }

  private func setupLayout() {
    // Indent (match VariantItemView indentation: 44px)
    let indent = NSView()
    indent.translatesAutoresizingMaskIntoConstraints = false
    indent.widthAnchor.constraint(equalToConstant: 44).isActive = true

    // Spacer
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

    // Button stack
    // Order: [HF] [Finder] [Delete]
    let buttonStack = NSStackView(views: [hfButton, finderButton, deleteButton])
    buttonStack.orientation = .horizontal
    buttonStack.alignment = .centerY
    buttonStack.spacing = 6

    // Root stack
    let rootStack = NSStackView(views: [indent, spacer, buttonStack])
    rootStack.orientation = .horizontal
    rootStack.alignment = .centerY
    rootStack.spacing = 0

    contentView.addSubview(rootStack)

    // Match VariantItemView padding
    rootStack.pinToSuperview(top: 0, leading: 10, trailing: 16, bottom: 0)

    // Constrain buttons
    Layout.constrainToIconSize(hfButton)
    Layout.constrainToIconSize(finderButton)
    Layout.constrainToIconSize(deleteButton)
  }

  private func configureViews() {
    Theme.configure(hfButton, symbol: "globe", tooltip: "Open on Hugging Face")
    Theme.configure(finderButton, symbol: "folder", tooltip: "Show in Finder")
    Theme.configure(deleteButton, symbol: "trash", tooltip: "Delete model")

    finderButton.target = self
    finderButton.action = #selector(didClickFinder)

    hfButton.target = self
    hfButton.action = #selector(didClickHF)

    deleteButton.target = self
    deleteButton.action = #selector(didClickDelete)
  }

  @objc private func didClickFinder() {
    actionHandler.showInFinder(model: model)
  }

  @objc private func didClickHF() {
    actionHandler.openHuggingFacePage(model: model)
  }

  @objc private func didClickDelete() {
    actionHandler.delete(model: model)
  }
}
