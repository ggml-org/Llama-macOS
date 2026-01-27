import AppKit
import Foundation

/// Controls the status bar item and its AppKit menu.
/// Breaks menu construction into section helpers so each concern stays focused.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
  private let statusItem: NSStatusItem
  private let modelManager: ModelManager
  private let server: LlamaServer
  private var actionHandler: ModelActionHandler!

  // Section State
  private var selectedFamily: String?
  private var expandedModelId: String?

  private var welcomePopover: WelcomePopover?

  // Store observer tokens for proper cleanup
  private var observers: [NSObjectProtocol] = []

  init(modelManager: ModelManager? = nil, server: LlamaServer? = nil) {
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.modelManager = modelManager ?? .shared
    self.server = server ?? .shared
    super.init()

    self.actionHandler = ModelActionHandler(
      modelManager: self.modelManager,
      server: self.server,
      onMembershipChange: { [weak self] _ in
        self?.rebuildMenuIfPossible()
        self?.refresh()
      }
    )

    configureStatusItem()
    setupObservers()
    showWelcomeIfNeeded()
  }

  func openMenu() {
    statusItem.button?.performClick(nil)
  }

  private func showWelcomeIfNeeded() {
    guard !UserSettings.hasSeenWelcome else { return }

    // Show after a short delay to ensure the status item is visible
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      guard let self else { return }
      let popover = WelcomePopover()
      popover.show(from: self.statusItem)
      self.welcomePopover = popover
      UserSettings.hasSeenWelcome = true
    }
  }

  private func configureStatusItem() {
    if let button = statusItem.button {
      button.image =
        NSImage(named: "MenuIcon")
        ?? NSImage(systemSymbolName: "brain", accessibilityDescription: nil)
      button.image?.isTemplate = true
      // Dim the icon when no model is loaded
      button.alphaValue = server.isAnyModelLoaded ? 1.0 : 0.35
    }

    let menu = NSMenu()
    menu.delegate = self
    menu.autoenablesItems = false
    statusItem.menu = menu
  }

  // MARK: - NSMenuDelegate

  func menuNeedsUpdate(_ menu: NSMenu) {
    guard menu === statusItem.menu else { return }
    rebuildMenu(menu)
  }

  func menuWillOpen(_ menu: NSMenu) {
    guard menu === statusItem.menu else { return }
    modelManager.refreshDownloadedModels()
  }

  func menuDidClose(_ menu: NSMenu) {
    guard menu === statusItem.menu else { return }

    // Reset section collapse state
    selectedFamily = nil
  }

  // MARK: - Menu Construction

  private func rebuildMenu(_ menu: NSMenu) {
    menu.removeAllItems()

    let view = HeaderView(server: server)
    menu.addItem(NSMenuItem.viewItem(with: view))
    menu.addItem(NSMenuItem.viewItem(with: SeparatorView()))

    addInstalledSection(to: menu)

    if let selectedFamily {
      addFamilyDetailSection(to: menu, familyName: selectedFamily)
    } else {
      addCatalogSection(to: menu)
    }

    addFooter(to: menu)
  }

  // MARK: - Live updates without closing submenus

  private func rebuildMenuIfPossible() {
    if let menu = statusItem.menu {
      rebuildMenu(menu)
    }
  }

  private func observe(_ name: Notification.Name, rebuildMenu: Bool = false) {
    let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main)
    {
      [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        if rebuildMenu {
          self.rebuildMenuIfPossible()
        }
        self.refresh()
      }
    }
    observers.append(observer)
  }

  // Observe server and download changes while the menu is open.
  private func setupObservers() {
    // Server started/stopped - update icon and views
    observe(.LBServerStateDidChange)

    // Server memory usage changed - update running model stats
    observe(.LBServerMemoryDidChange)

    // Model status changed (loaded/unloaded)
    observe(.LBModelStatusDidChange)

    // Download progress updated - refresh progress indicators
    observe(.LBModelDownloadsDidChange)

    // Model downloaded or deleted - rebuild both installed and catalog sections
    observe(.LBModelDownloadedListDidChange, rebuildMenu: true)

    // User settings changed - rebuild menu
    observe(.LBUserSettingsDidChange, rebuildMenu: true)

    // Download failed - show alert
    let failObserver = NotificationCenter.default.addObserver(
      forName: .LBModelDownloadDidFail, object: nil, queue: .main
    ) { [weak self] note in
      MainActor.assumeIsolated {
        self?.handleDownloadFailure(notification: note)
      }
    }
    observers.append(failObserver)

    refresh()
  }

  deinit {
    // Remove all notification observers to prevent dangling references
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  private func handleDownloadFailure(notification: Notification) {
    guard let userInfo = notification.userInfo,
      let model = userInfo["model"] as? CatalogEntry,
      let error = userInfo["error"] as? String
    else { return }

    // Activate the app to ensure the modal alert appears in front of other windows
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "Download Failed"
    alert.informativeText = "Could not download \(model.displayName).\n\nDetails: \(error)"
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  private func refresh() {
    // Update icon opacity: full when loaded, mid when loading, dim when idle
    if let button = statusItem.button {
      if server.isAnyModelLoaded {
        button.alphaValue = 1.0
      } else if server.isAnyModelLoading {
        button.alphaValue = 0.65
      } else {
        button.alphaValue = 0.35
      }
    }

    guard let menu = statusItem.menu else { return }
    for item in menu.items {
      if let view = item.view as? HeaderView {
        view.refresh()
      } else if let view = item.view as? ModelItemView {
        view.refresh()
      }
    }
  }

  private func addFooter(to menu: NSMenu) {
    menu.addItem(NSMenuItem.viewItem(with: SeparatorView()))

    let footerView = FooterView(
      onCheckForUpdates: { [weak self] in self?.checkForUpdates() },
      onOpenSettings: { [weak self] in self?.openSettings() },
      onQuit: { [weak self] in self?.quitApp() }
    )

    let item = NSMenuItem.viewItem(with: footerView)
    item.isEnabled = true
    menu.addItem(item)
  }

  @objc private func checkForUpdates() {
    NotificationCenter.default.post(name: .LBCheckForUpdates, object: nil)
  }

  @objc private func quitApp() {
    NSApplication.shared.terminate(nil)
  }

  // MARK: - Installed Section

  private func addInstalledSection(to menu: NSMenu) {
    let models = modelManager.managedModels
    guard !models.isEmpty else { return }

    // Build the /models endpoint URL
    // For 0.0.0.0, show the actual local IP for user convenience
    let host: String
    if let bindAddress = UserSettings.networkBindAddress {
      host =
        bindAddress == "0.0.0.0"
        ? (LlamaServer.getLocalIpAddress() ?? "0.0.0.0")
        : bindAddress
    } else {
      host = "localhost"
    }
    let modelsUrl = URL(string: "http://\(host):\(LlamaServer.defaultPort)/models")

    // Create family item (not collapsible) with link to /models endpoint
    let familyView = FamilyItemView(
      family: "Installed",
      sizes: [],
      linkText: "models",
      linkUrl: modelsUrl
    )
    let familyItem = NSMenuItem.viewItem(with: familyView)
    menu.addItem(familyItem)

    // Always show models
    buildInstalledItems(models).forEach { menu.addItem($0) }

    // Trailing separator after installed section
    menu.addItem(NSMenuItem.viewItem(with: SeparatorView()))
  }

  private func buildInstalledItems(_ models: [CatalogEntry]) -> [NSMenuItem] {
    var items = [NSMenuItem]()

    for model in models {
      let isExpanded = expandedModelId == model.id

      let view = ModelItemView(
        model: model,
        server: server,
        modelManager: modelManager,
        actionHandler: actionHandler,
        isExpanded: isExpanded,
        onExpand: { [weak self] in
          self?.toggleExpansion(for: model.id)
        }
      )
      items.append(NSMenuItem.viewItem(with: view))

      if isExpanded {
        // Single container for all expanded details
        let detailsView = ExpandedModelDetailsView(
          model: model,
          actionHandler: actionHandler
        )
        items.append(NSMenuItem.viewItem(with: detailsView))
      }
    }
    return items
  }

  private func toggleExpansion(for modelId: String) {
    if expandedModelId == modelId {
      expandedModelId = nil
    } else {
      expandedModelId = modelId
    }
    rebuildMenuIfPossible()
  }

  // MARK: - Catalog Section

  private func addFamilyDetailSection(to menu: NSMenu, familyName: String) {
    guard let family = Catalog.families.first(where: { $0.name == familyName }) else { return }

    // Back Item
    let backView = TextItemView(text: "back", showBackArrow: true) { [weak self] in
      self?.selectedFamily = nil
      self?.rebuildMenuIfPossible()
    }
    menu.addItem(NSMenuItem.viewItem(with: backView))

    // Family Title
    let titleView = TextItemView(text: familyName)
    menu.addItem(NSMenuItem.viewItem(with: titleView))

    if let description = family.description {
      let descriptionView = TextItemView(text: description, style: .description)
      menu.addItem(NSMenuItem.viewItem(with: descriptionView))
    }

    let validModels = family.selectableModels()
    let availableModels = validModels.filter {
      modelManager.status(for: $0) == .available
    }

    for model in availableModels {
      let view = ModelItemView(
        model: model,
        server: server,
        modelManager: modelManager,
        actionHandler: actionHandler,
        isInCatalog: true
      )
      menu.addItem(NSMenuItem.viewItem(with: view))
    }
  }

  private func addCatalogSection(to menu: NSMenu) {
    var items: [NSMenuItem] = []

    for family in Catalog.families {
      let validModels = family.selectableModels()

      let availableModels = validModels.filter {
        modelManager.status(for: $0) == .available
      }

      if availableModels.isEmpty {
        continue
      }

      // Collect unique sizes for family item from available models
      let sizes =
        availableModels
        .sorted { $0.parameterCount < $1.parameterCount }
        .map { model -> (String, Bool) in
          let sizeName = model.size
            .replacingOccurrences(of: " Thinking", with: "")
            .replacingOccurrences(of: " Reasoning", with: "")
          return (sizeName, model.isCompatible())
        }
        .reduce(into: [(String, Bool)]()) { result, item in
          if let lastIndex = result.indices.last, result[lastIndex].0 == item.0 {
            if item.1 { result[lastIndex].1 = true }
          } else {
            result.append(item)
          }
        }

      let familyView = FamilyItemView(
        family: family.name,
        sizes: sizes,
        description: family.description
      ) { [weak self] familyName in
        self?.selectedFamily = familyName
        self?.rebuildMenuIfPossible()
      }
      let familyItem = NSMenuItem.viewItem(with: familyView)
      items.append(familyItem)
    }

    guard !items.isEmpty else { return }

    items.forEach { menu.addItem($0) }
  }

  // MARK: - Settings Section

  private func openSettings() {
    // Close the menu first, then open settings window
    statusItem.menu?.cancelTracking()
    NotificationCenter.default.post(name: .LBShowSettings, object: nil)
  }
}
