import AppKit
import Foundation

/// Controls the status bar item and its AppKit menu.
/// Breaks menu construction into section helpers so each concern stays focused.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
  private let statusItem: NSStatusItem
  private let modelManager: ModelManager
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
  private let observer = NotificationObserver()
  private weak var currentlyHighlightedView: ItemView?

  init(modelManager: ModelManager? = nil, server: LlamaServer? = nil) {
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.modelManager = modelManager ?? .shared
    self.server = server ?? .shared
    super.init()
    configureStatusItem()
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
    guard menu === statusItem.menu else { return }
    currentlyHighlightedView?.setHighlight(false)
    currentlyHighlightedView = nil
    observer.removeAll()
    isSettingsVisible = false
  }

  func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
    // Only manage highlights for enabled items in the root menu (family items, settings, footer).
    // Submenu model items remain disabled and use their own tracking areas for hover.
    // This optimization reduces highlight updates from O(n) to O(1) by tracking only the current view.
    guard menu === statusItem.menu else { return }
    let highlighted = item?.view as? ItemView

    if currentlyHighlightedView !== highlighted {
      currentlyHighlightedView?.setHighlight(false)
      highlighted?.setHighlight(true)
      currentlyHighlightedView = highlighted
    }
  }

  // MARK: - Menu Construction

  private func rebuildMenu(_ menu: NSMenu) {
    menu.removeAllItems()

    headerSection.add(to: menu)

    installedSection.add(to: menu)
    catalogSection.add(to: menu)
    footerSection.add(to: menu, menuWidth: menuWidth)

    if isSettingsVisible {
      menu.addItem(.separator())
      settingsSection.add(to: menu, menuWidth: menuWidth)
    }

    if menu.size.width > 0 {
      menuWidth = menu.size.width
    }
  }

  // MARK: - Live updates without closing submenus

  /// Called from model rows when a user starts/cancels a download.
  /// Rebuilds both installed and catalog sections to reflect changes while keeping submenus open.
  private func didChangeDownloadStatus(for _: CatalogEntry) {
    if let menu = statusItem.menu {
      installedSection.rebuild(in: menu)
      catalogSection.rebuild(in: menu)
    }
    refresh()
  }

  // Observe server and download changes while the menu is open.
  private func addObservers() {
    observer.removeAll()

    // Server started/stopped - update icon and views
    observer.observe(.LBServerStateDidChange) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refresh()
      }
    }

    // Server memory usage changed - update running model stats
    observer.observe(.LBServerMemoryDidChange) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refresh()
      }
    }

    // Download progress updated - refresh progress indicators
    observer.observe(.LBModelDownloadsDidChange) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refresh()
      }
    }

    // Model downloaded or deleted - rebuild both installed and catalog sections
    observer.observe(.LBModelDownloadedListDidChange) { [weak self] _ in
      MainActor.assumeIsolated {
        if let menu = self?.statusItem.menu {
          self?.installedSection.rebuild(in: menu)
          self?.catalogSection.rebuild(in: menu)
        }
        self?.refresh()
      }
    }

    // Settings visibility toggled - rebuild menu
    observer.observe(.LBToggleSettingsVisibility) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.isSettingsVisible.toggle()
        if let menu = self?.statusItem.menu {
          self?.rebuildMenu(menu)
        }
      }
    }

    // User settings changed (e.g., show quantized models) - rebuild menu
    observer.observe(.LBUserSettingsDidChange) { [weak self] _ in
      MainActor.assumeIsolated {
        if let menu = self?.statusItem.menu {
          self?.rebuildMenu(menu)
        }
      }
    }

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

    headerSection.refresh()
    installedSection.refresh()
    catalogSection.refresh()
  }
}
