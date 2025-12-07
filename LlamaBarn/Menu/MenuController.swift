import AppKit
import Foundation

/// Controls the status bar item and its AppKit menu.
/// Breaks menu construction into section helpers so each concern stays focused.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
  private let statusItem: NSStatusItem
  private let modelManager: ModelManager
  private let server: LlamaServer

  // Section State
  private var isInstalledCollapsed = false
  private var isSettingsOpen = false
  private var collapsedFamilies: Set<String> = []
  private var hasInitializedCollapseState = false

  private var welcomePopover: WelcomePopover?

  init(modelManager: ModelManager? = nil, server: LlamaServer? = nil) {
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.modelManager = modelManager ?? .shared
    self.server = server ?? .shared
    super.init()
    configureStatusItem()
    setupObservers()
    showWelcomeIfNeeded()
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
        NSImage(named: server.isRunning ? "MenuIconOn" : "MenuIconOff")
        ?? NSImage(systemSymbolName: "brain", accessibilityDescription: nil)
      button.image?.isTemplate = true
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
    isInstalledCollapsed = false
    isSettingsOpen = false
    collapsedFamilies.removeAll()
    hasInitializedCollapseState = false
  }

  // MARK: - Menu Construction

  private func rebuildMenu(_ menu: NSMenu) {
    menu.removeAllItems()

    let view = HeaderView(server: server)
    menu.addItem(NSMenuItem.viewItem(with: view))
    menu.addItem(.separator())

    addInstalledSection(to: menu)
    addCatalogSection(to: menu)
    addFooter(to: menu)
    addSettingsSection(to: menu)
  }

  // MARK: - Live updates without closing submenus

  /// Called from model rows when a user starts/cancels a download.
  /// Rebuilds both installed and catalog sections to reflect changes while keeping submenus open.
  private func didChangeDownloadStatus(for _: CatalogEntry) {
    if let menu = statusItem.menu {
      rebuildMenu(menu)
    }
    refresh()
  }

  /// Helper to observe a notification and call refresh on the main actor
  private func observeAndRefresh(_ name: Notification.Name) {
    NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated {
        self?.refresh()
      }
    }
  }

  /// Helper to observe a notification and rebuild the menu on the main actor
  private func observeAndRebuild(_ name: Notification.Name) {
    NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated {
        if let menu = self?.statusItem.menu {
          self?.rebuildMenu(menu)
        }
        self?.refresh()
      }
    }
  }

  // Observe server and download changes while the menu is open.
  private func setupObservers() {
    // Server started/stopped - update icon and views
    observeAndRefresh(.LBServerStateDidChange)

    // Server memory usage changed - update running model stats
    observeAndRefresh(.LBServerMemoryDidChange)

    // Download progress updated - refresh progress indicators
    observeAndRefresh(.LBModelDownloadsDidChange)

    // Model downloaded or deleted - rebuild both installed and catalog sections
    observeAndRebuild(.LBModelDownloadedListDidChange)

    // User settings changed (e.g., prefer quantized models) - rebuild menu
    observeAndRebuild(.LBUserSettingsDidChange)

    refresh()
  }

  private func refresh() {
    if let button = statusItem.button {
      let running = server.isRunning
      let imageName = running ? "MenuIconOn" : "MenuIconOff"
      if button.image?.name() != imageName {
        button.image = NSImage(named: imageName) ?? button.image
        button.image?.isTemplate = true
      }
    }

    guard let menu = statusItem.menu else { return }
    for item in menu.items {
      if let view = item.view as? HeaderView {
        view.refresh()
      } else if let view = item.view as? InstalledModelItemView {
        view.refresh()
      } else if let view = item.view as? CatalogModelItemView {
        view.refresh()
      }
    }
  }

  private func addFooter(to menu: NSMenu) {
    menu.addItem(.separator())

    let footerView = FooterView(
      onCheckForUpdates: { [weak self] in self?.checkForUpdates() },
      onOpenSettings: { [weak self] in self?.toggleSettings() },
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
    let models = installedModels()
    guard !models.isEmpty else { return }

    // Create header with model count when collapsed
    let sizes = isInstalledCollapsed ? ["\(models.count)"] : []
    let headerView = FamilyHeaderView(
      family: "Installed",
      sizes: sizes,
      isCollapsed: isInstalledCollapsed
    ) { [weak self] _ in
      self?.toggleInstalledCollapsed()
    }
    let headerItem = NSMenuItem.viewItem(with: headerView)
    menu.addItem(headerItem)

    // Only show models if not collapsed
    if !isInstalledCollapsed {
      buildInstalledItems(models).forEach { menu.addItem($0) }
    }
  }

  private func toggleInstalledCollapsed() {
    isInstalledCollapsed.toggle()
    if let menu = statusItem.menu {
      rebuildMenu(menu)
    }
  }

  private func installedModels() -> [CatalogEntry] {
    let downloading = Catalog.allModels().filter { modelManager.isDownloading($0) }
    return (modelManager.downloadedModels + downloading)
      .sorted(by: CatalogEntry.displayOrder(_:_:))
  }

  private func buildInstalledItems(_ models: [CatalogEntry]) -> [NSMenuItem] {
    return models.map { model in
      let view = InstalledModelItemView(
        model: model,
        server: server,
        modelManager: modelManager
      ) { [weak self] entry in
        self?.didChangeDownloadStatus(for: entry)
      }
      return NSMenuItem.viewItem(with: view)
    }
  }

  // MARK: - Catalog Section

  private func addCatalogSection(to menu: NSMenu) {
    // Initialize families as collapsed when menu first opens.
    // On subsequent rebuilds during the same session (e.g., toggling settings),
    // preserve the collapse state.
    if !hasInitializedCollapseState {
      collapsedFamilies = Set(Catalog.families.map { $0.name })
      hasInitializedCollapseState = true
    }

    var items: [NSMenuItem] = []

    for family in Catalog.families {
      let preferQuantized = UserSettings.preferQuantizedModels
      let validModels = family.selectableModels(preferQuantized: preferQuantized)

      // Only show family if there are models available to install
      let availableModels = validModels.filter {
        !modelManager.isInstalled($0) && !modelManager.isDownloading($0)
      }

      if availableModels.isEmpty {
        continue
      }

      // Collect unique sizes for header from available models
      let sizes = availableModels.map { $0.sizeLabel }
        .reduce(into: [String]()) { result, size in
          if result.last != size { result.append(size) }
        }

      let headerView = FamilyHeaderView(
        family: family.name,
        sizes: sizes,
        isCollapsed: collapsedFamilies.contains(family.name)
      ) { [weak self] familyName in
        self?.toggleFamilyCollapsed(familyName)
      }
      let headerItem = NSMenuItem.viewItem(with: headerView)
      items.append(headerItem)

      if !collapsedFamilies.contains(family.name) {
        for model in availableModels {
          let view = CatalogModelItemView(model: model, modelManager: modelManager) {
            [weak self] in
            self?.didChangeDownloadStatus(for: model)
          }
          items.append(NSMenuItem.viewItem(with: view))
        }
      }
    }

    guard !items.isEmpty else { return }

    menu.addItem(.separator())

    items.forEach { menu.addItem($0) }
  }

  private func toggleFamilyCollapsed(_ family: String) {
    if collapsedFamilies.contains(family) {
      collapsedFamilies.remove(family)
    } else {
      collapsedFamilies.insert(family)
    }
    if let menu = statusItem.menu {
      rebuildMenu(menu)
    }
  }

  // MARK: - Settings Section

  private func addSettingsSection(to menu: NSMenu) {
    guard isSettingsOpen else { return }

    menu.addItem(.separator())

    // Launch at Login
    let launchAtLoginItem = NSMenuItem.viewItem(
      with: SettingsItemView(
        title: "Launch at Login",
        getValue: { LaunchAtLogin.isEnabled },
        onToggle: { newValue in
          _ = LaunchAtLogin.setEnabled(newValue)
        }
      ))
    menu.addItem(launchAtLoginItem)

    // Prefer Quantized Models
    let preferQuantizedItem = NSMenuItem.viewItem(
      with: SettingsItemView(
        title: "Prefer Quantized Models",
        subtitle: "Use compressed models to save memory and disk space",
        getValue: { UserSettings.preferQuantizedModels },
        onToggle: { newValue in
          UserSettings.preferQuantizedModels = newValue
        }
      ))
    menu.addItem(preferQuantizedItem)

    #if DEBUG
      // Expose to Network
      let exposeToNetworkItem = NSMenuItem.viewItem(
        with: SettingsItemView(
          title: "Expose to Network",
          subtitle: "Bind to 0.0.0.0 instead of localhost, dev-only",
          getValue: { UserSettings.exposeToNetwork },
          onToggle: { newValue in
            UserSettings.exposeToNetwork = newValue
          }
        ))
      menu.addItem(exposeToNetworkItem)
    #endif

  }

  private func toggleSettings() {
    isSettingsOpen.toggle()
    if let menu = statusItem.menu {
      rebuildMenu(menu)
    }
  }
}
