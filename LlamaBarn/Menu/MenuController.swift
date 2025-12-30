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
  private var selectedFamily: String?

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
    selectedFamily = nil
  }

  // MARK: - Menu Construction

  private func rebuildMenu(_ menu: NSMenu) {
    menu.removeAllItems()

    let view = HeaderView(server: server)
    menu.addItem(NSMenuItem.viewItem(with: view))
    menu.addItem(.separator())

    addInstalledSection(to: menu)

    if let selectedFamily {
      addFamilyDetailSection(to: menu, familyName: selectedFamily)
    } else {
      addCatalogSection(to: menu)
    }

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
      sizes: []
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

  private func addFamilyDetailSection(to menu: NSMenu, familyName: String) {
    menu.addItem(.separator())

    // Back Header
    let backView = FamilyHeaderView(
      family: familyName,
      sizes: [],
      showChevron: false,
      showBackChevron: true
    ) { [weak self] _ in
      self?.selectedFamily = nil
      self?.rebuildMenuIfPossible()
    }
    menu.addItem(NSMenuItem.viewItem(with: backView))

    guard let family = Catalog.families.first(where: { $0.name == familyName }) else { return }
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

      // Collect unique sizes for header from available models
      let sizes = availableModels.map {
        $0.size
          .replacingOccurrences(of: " Thinking", with: "")
          .replacingOccurrences(of: " Reasoning", with: "")
      }
      .reduce(into: [String]()) { result, size in
        if result.last != size { result.append(size) }
      }

      let headerView = FamilyHeaderView(
        family: family.name,
        sizes: sizes
      ) { [weak self] familyName in
        self?.selectedFamily = familyName
        self?.rebuildMenuIfPossible()
      }
      let headerItem = NSMenuItem.viewItem(with: headerView)
      items.append(headerItem)
    }

    guard !items.isEmpty else { return }

    menu.addItem(.separator())

    items.forEach { menu.addItem($0) }
  }

  // MARK: - Settings Section

  private func addSettingsSection(to menu: NSMenu) {
    guard isSettingsOpen else { return }

    menu.addItem(.separator())
    menu.addItem(makeLaunchAtLoginItem())
    menu.addItem(makeContextLengthItem())
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

  private func toggleSettings() {
    isSettingsOpen.toggle()
    rebuildMenuIfPossible()
  }
}
