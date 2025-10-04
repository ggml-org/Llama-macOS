import AppKit
import Foundation

/// Controls the status bar item and its AppKit menu.
/// Breaks menu construction into section helpers so each concern stays focused.
@MainActor
final class Controller: NSObject, NSMenuDelegate {
  private let statusItem: NSStatusItem
  private let modelManager: Manager
  private let server: LlamaServer

  private lazy var headerSection = MenuHeaderSection(server: server)
  private let settingsSection = MenuSettingsSection()
  private lazy var installedSection = InstalledSection(
    modelManager: modelManager,
    server: server
  ) { [weak self] model in
    self?.didChangeDownloadStatus(for: model)
  }
  private lazy var catalogSection = CatalogSection(
    modelManager: modelManager
  ) { [weak self] model in
    self?.didChangeDownloadStatus(for: model)
  }
  private let footerSection = FooterSection()

  private var isSettingsVisible = false
  private var menuWidth: CGFloat = 260
  private var observers: [NSObjectProtocol] = []
  private var refreshWorkItem: DispatchWorkItem?

  init(modelManager: Manager = .shared, server: LlamaServer = .shared) {
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.modelManager = modelManager
    self.server = server
    super.init()
    configureStatusItem()
  }

  deinit {
    refreshWorkItem?.cancel()
    observers.forEach { NotificationCenter.default.removeObserver($0) }
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
    addObservers()
  }

  func menuDidClose(_ menu: NSMenu) {
    menu.items.forEach { (item: NSMenuItem) in
      (item.view as? ItemView)?.setHoverHighlight(false)
    }
    guard menu === statusItem.menu else { return }
    refreshWorkItem?.cancel()
    refreshWorkItem = nil
    removeObservers()
    isSettingsVisible = false
  }

  func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
    let highlighted = item?.view as? ItemView
    menu.items.forEach { (entry: NSMenuItem) in
      guard let row = entry.view as? ItemView else { return }
      row.setHoverHighlight(row === highlighted)
    }
  }

  // MARK: - Menu Construction

  private func rebuildMenu(_ menu: NSMenu) {
    menu.removeAllItems()

    headerSection.add(to: menu, isSettingsVisible: isSettingsVisible)

    if isSettingsVisible {
      settingsSection.add(to: menu, menuWidth: menuWidth)
      menu.addItem(.separator())
    }

    installedSection.add(to: menu)
    catalogSection.add(to: menu)
    footerSection.add(to: menu, menuWidth: menuWidth)

    if menu.size.width > 0 {
      menuWidth = menu.size.width
    }
  }

  // MARK: - Live updates without closing submenus

  /// Called from model rows when a user starts/cancels a download.
  /// Rebuilds the installed section to reflect membership changes while keeping submenus open.
  private func didChangeDownloadStatus(for _: CatalogEntry) {
    if let menu = statusItem.menu {
      installedSection.rebuildIfNeeded(in: menu)
    }
    performRefresh()
  }

  // Observe server and download changes while the menu is open.
  private func addObservers() {
    removeObservers()
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(forName: .LBServerStateDidChange, object: nil, queue: .main) {
        [weak self] _ in
        self?.performRefresh()
      })
    observers.append(
      center.addObserver(forName: .LBServerMemoryDidChange, object: nil, queue: .main) {
        [weak self] _ in
        self?.performRefresh()
      })
    observers.append(
      center.addObserver(forName: .LBModelDownloadsDidChange, object: nil, queue: .main) {
        [weak self] _ in
        self?.performRefresh()
      })
    observers.append(
      center.addObserver(forName: .LBModelDownloadedListDidChange, object: nil, queue: .main) {
        [weak self] _ in
        // Installed list changed (download completed or model deleted) - rebuild section
        if let menu = self?.statusItem.menu {
          self?.installedSection.rebuildIfNeeded(in: menu)
        }
        self?.performRefresh()
      })
    observers.append(
      center.addObserver(forName: .LBToggleSettingsVisibility, object: nil, queue: .main) {
        [weak self] _ in
        self?.isSettingsVisible.toggle()
        if let menu = self?.statusItem.menu {
          self?.rebuildMenu(menu)
        }
      })
    observers.append(
      center.addObserver(forName: .LBUserSettingsDidChange, object: nil, queue: .main) {
        [weak self] _ in
        if let menu = self?.statusItem.menu {
          self?.rebuildMenu(menu)
        }
      })
    performRefresh()
  }

  private func removeObservers() {
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    observers.removeAll()
  }

  private func performRefresh() {
    // Debounce rapid refresh calls to prevent excessive UI updates.
    // Cancel any pending refresh and schedule a new one after 50ms.
    // This coalesces multiple notifications within a single run loop cycle.
    refreshWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      self?.executeRefresh()
    }
    refreshWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
  }

  private func executeRefresh() {
    if let button = statusItem.button {
      let running = server.isRunning
      let imageName = running ? "MenuIconOn" : "MenuIconOff"
      if button.image?.name() != imageName {
        button.image = NSImage(named: imageName) ?? button.image
        button.image?.isTemplate = true
      }
    }

    headerSection.refresh()

    // Refresh existing views in place for progress updates without rebuilding section structure
    statusItem.menu?.items.forEach { menuItem in
      if let view = menuItem.view as? InstalledModelItemView { view.refresh() }
      if let submenu = menuItem.submenu {
        submenu.items.forEach { subItem in
          if let view = subItem.view as? CatalogModelItemView { view.refresh() }
        }
      }
      if let famView = menuItem.view as? FamilyItemView { famView.refresh() }
    }
  }
}
