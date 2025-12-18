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
  private var isSettingsOpen = false
  private var collapsedFamilies: Set<String> = Set(Catalog.families.map { $0.name })

  private var welcomePopover: WelcomePopover?

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

    // Create header (not collapsible)
    let headerView = FamilyHeaderView(
      family: "Installed",
      sizes: [],
      isCollapsed: false
    )
    let headerItem = NSMenuItem.viewItem(with: headerView)
    menu.addItem(headerItem)

    // Always show models
    buildInstalledItems(models).forEach { menu.addItem($0) }
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
        modelManager: modelManager,
        actionHandler: actionHandler
      )
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
            modelManager: modelManager,
            actionHandler: actionHandler,
            isInCatalog: true
          )
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
    menu.addItem(makeLaunchAtLoginItem())
    menu.addItem(makeContextLengthItem())
    menu.addItem(makeMemoryLimitItem())
  }

  private func makeLaunchAtLoginItem() -> NSMenuItem {
    NSMenuItem.viewItem(
      with: SettingsItemView(
        title: "Launch at login",
        getValue: { LaunchAtLogin.isEnabled },
        onToggle: { newValue in
          _ = LaunchAtLogin.setEnabled(newValue)
        }
      ))
  }

  private func makeContextLengthItem() -> NSMenuItem {
    let contextWindowLabels = UserSettings.ContextWindowSize.allCases.map { $0.displayName }
    return NSMenuItem.viewItem(
      with: SettingsSegmentedView(
        title: "Context length",
        infoText: "Higher context lengths use more memory.",
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
  }

  private func makeMemoryLimitItem() -> NSMenuItem {
    let memoryCaps = UserSettings.availableMemoryUsageCaps
    let memoryCapLabels = memoryCaps.map { fraction -> String in
      let gb = Double(SystemMemory.memoryMb) * fraction / 1024.0
      return String(format: "%.0f GB", gb)
    }
    return NSMenuItem.viewItem(
      with: SettingsSegmentedView(
        title: "Memory limit",
        infoText: "Limits the amount of memory models can use.",
        labels: memoryCapLabels,
        getSelectedIndex: {
          let current = UserSettings.memoryUsageCap
          return memoryCaps.firstIndex { abs($0 - current) < 0.001 } ?? (memoryCaps.count - 1)
        },
        onSelect: { index in
          if index >= 0 && index < memoryCaps.count {
            UserSettings.memoryUsageCap = memoryCaps[index]
          }
        }
      ))
  }

  private func toggleSettings() {
    isSettingsOpen.toggle()
    rebuildMenuIfPossible()
  }
}
