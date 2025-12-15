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
  private var collapsedFamilies: Set<String> = Set(Catalog.families.map { $0.name })

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
    collapsedFamilies = Set(Catalog.families.map { $0.name })
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
    rebuildMenuIfPossible()
    refresh()
  }

  private func rebuildMenuIfPossible() {
    if let menu = statusItem.menu {
      rebuildMenu(menu)
    }
  }

  private func observe(_ name: Notification.Name, rebuildMenu: Bool = false) {
    NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        if rebuildMenu {
          self.rebuildMenuIfPossible()
        }
        self.refresh()
      }
    }
  }

  // Observe server and download changes while the menu is open.
  private func setupObservers() {
    // Server started/stopped - update icon and views
    observe(.LBServerStateDidChange)

    // Server memory usage changed - update running model stats
    observe(.LBServerMemoryDidChange)

    // Download progress updated - refresh progress indicators
    observe(.LBModelDownloadsDidChange)

    // Model downloaded or deleted - rebuild both installed and catalog sections
    observe(.LBModelDownloadedListDidChange, rebuildMenu: true)

    // User settings changed - rebuild menu
    observe(.LBUserSettingsDidChange, rebuildMenu: true)

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
      } else if let view = item.view as? ModelItemView {
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
    rebuildMenuIfPossible()
  }

  private func installedModels() -> [CatalogEntry] {
    return (modelManager.downloadedModels + modelManager.downloadingModels)
      .sorted(by: CatalogEntry.displayOrder(_:_:))
  }

  private func buildInstalledItems(_ models: [CatalogEntry]) -> [NSMenuItem] {
    return models.map { model in
      let view = ModelItemView(
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
    var items: [NSMenuItem] = []

    for family in Catalog.families {
      let validModels = family.selectableModels()

      // Only show family if there are models available to install
      let availableModels = validModels.filter {
        modelManager.status(for: $0) == .available
      }

      if availableModels.isEmpty {
        continue
      }

      // Collect unique sizes for header from available models
      let sizes = availableModels.map { $0.size }
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
          let view = ModelItemView(
            model: model,
            server: server,
            modelManager: modelManager
          ) { [weak self] entry in
            self?.didChangeDownloadStatus(for: entry)
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
    rebuildMenuIfPossible()
  }

  // MARK: - Settings Section

  private func addSettingsSection(to menu: NSMenu) {
    guard isSettingsOpen else { return }

    menu.addItem(.separator())

    // Launch at login
    let launchAtLoginItem = NSMenuItem.viewItem(
      with: SettingsItemView(
        title: "Launch at login",
        getValue: { LaunchAtLogin.isEnabled },
        onToggle: { newValue in
          _ = LaunchAtLogin.setEnabled(newValue)
        }
      ))
    menu.addItem(launchAtLoginItem)

    // Show mem usage for 4k ctx
    let showMemUsageItem = NSMenuItem.viewItem(
      with: SettingsItemView(
        title: "Show estimated memory usage",
        getValue: { UserSettings.showEstimatedMemoryUsage },
        onToggle: { newValue in
          UserSettings.showEstimatedMemoryUsage = newValue
        }
      ))
    menu.addItem(showMemUsageItem)

    // Default context length
    let contextWindowLabels = UserSettings.ContextWindowSize.allCases.map { $0.displayName }
    let defaultContextWindowItem = NSMenuItem.viewItem(
      with: SettingsSegmentedView(
        title: "Context length",
        subtitle: nil,
        labels: contextWindowLabels,
        getSelectedIndex: {
          UserSettings.ContextWindowSize.allCases.firstIndex(of: UserSettings.defaultContextWindow)
            ?? 0
        },
        onSelect: { index in
          if index >= 0 && index < UserSettings.ContextWindowSize.allCases.count {
            UserSettings.defaultContextWindow = UserSettings.ContextWindowSize.allCases[index]
          }
        }
      ))
    menu.addItem(defaultContextWindowItem)

  }

  private func toggleSettings() {
    isSettingsOpen.toggle()
    rebuildMenuIfPossible()
  }
}
