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
  private var expandedModelIds: Set<String> = []
  private var infoExpandedModelIds: Set<String> = []  // Models with info text expanded

  private var hintPopover: HintPopover?

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
      self.showHint("Hello, I'm Llama")
      UserSettings.hasSeenWelcome = true
    }
  }

  /// Shows a short speech-bubble message anchored to the menu bar icon.
  /// Replaces any currently visible hint.
  func showHint(_ message: String) {
    let popover = HintPopover(message: message)
    popover.show(from: statusItem)
    hintPopover = popover
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
    expandedModelIds.removeAll()
    infoExpandedModelIds.removeAll()
  }

  // MARK: - Menu Construction

  private func rebuildMenu(_ menu: NSMenu) {
    menu.removeAllItems()

    let view = HeaderView(server: server)
    menu.addItem(NSMenuItem.viewItem(with: view))
    menu.addItem(NSMenuItem.viewItem(with: SeparatorView()))

    // Show warning if custom cache directory is unavailable (e.g., external drive unplugged)
    if UserSettings.hasCustomHFCacheDirectory
      && !FileManager.default.fileExists(atPath: UserSettings.hfCacheDirectory.path)
    {
      addFolderWarning(to: menu)
    }

    addInstalledSection(to: menu)
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

    // Model downloaded or deleted - rebuild the installed-models section
    observe(.LBModelDownloadedListDidChange, rebuildMenu: true)

    // User settings changed - rebuild menu
    observe(.LBUserSettingsDidChange, rebuildMenu: true)

    // A background flow (e.g. DeeplinkHandler) wants to surface a hint bubble.
    let hintObserver = NotificationCenter.default.addObserver(
      forName: .LBShowMenuHint, object: nil, queue: .main
    ) { [weak self] note in
      MainActor.assumeIsolated {
        guard let msg = note.userInfo?["message"] as? String else { return }
        self?.showHint(msg)
      }
    }
    observers.append(hintObserver)

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
      let model = userInfo["model"] as? Model,
      let error = userInfo["error"] as? String
    else { return }

    // Activate the app to ensure the modal alert appears in front of other windows
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "Download Failed"
    alert.informativeText = "Could not download \(model.displayName).\n\n\(error)"
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
    guard !models.isEmpty else {
      menu.addItem(NSMenuItem.viewItem(with: EmptyStateView()))
      return
    }

    // "Installed" header with a link to the running server's /models endpoint
    let host = LlamaServer.resolvedHost
    let modelsUrl = URL(string: "http://\(host):\(LlamaServer.defaultPort)/models")
    let header = InstalledHeaderView(linkText: "models", linkUrl: modelsUrl)
    menu.addItem(NSMenuItem.viewItem(with: header))

    // Always show models
    buildInstalledItems(models).forEach { menu.addItem($0) }
  }

  private func buildInstalledItems(_ models: [Model]) -> [NSMenuItem] {
    var items = [NSMenuItem]()

    for model in models {
      let isExpanded = expandedModelIds.contains(model.id)

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
        let isInfoExpanded = infoExpandedModelIds.contains(model.id)
        let detailsView = ExpandedModelDetailsView(
          model: model,
          actionHandler: actionHandler,
          server: server,
          isInfoExpanded: isInfoExpanded,
          onInfoToggle: { [weak self] expanded in
            if expanded {
              self?.infoExpandedModelIds.insert(model.id)
            } else {
              self?.infoExpandedModelIds.remove(model.id)
            }
          }
        )
        items.append(NSMenuItem.viewItem(with: detailsView))
      }
    }
    return items
  }

  private func toggleExpansion(for modelId: String) {
    if expandedModelIds.contains(modelId) {
      expandedModelIds.remove(modelId)
      // Also collapse info when model collapses
      infoExpandedModelIds.remove(modelId)
    } else {
      expandedModelIds.insert(modelId)
    }
    rebuildMenuIfPossible()
  }

  // MARK: - Settings Section

  private func openSettings() {
    // Close the menu first, then open settings window
    statusItem.menu?.cancelTracking()
    NotificationCenter.default.post(name: .LBShowSettings, object: nil)
  }

  // MARK: - Folder Warning

  /// Adds a warning when the custom models folder is unavailable (e.g., external drive unplugged)
  private func addFolderWarning(to menu: NSMenu) {
    let warningView = TextItemView(
      text: "Cache directory not available. Check Settings.",
      style: .description,
      onAction: { [weak self] in
        self?.openSettings()
      }
    )
    menu.addItem(NSMenuItem.viewItem(with: warningView))
    menu.addItem(NSMenuItem.viewItem(with: SeparatorView()))
  }
}
