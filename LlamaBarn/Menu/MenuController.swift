import AppKit
import Foundation
import SwiftUI

/// Controls the status bar item and its AppKit menu.
/// Breaks menu construction into section helpers so each concern stays focused.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
  private let statusItem: NSStatusItem
  private let modelManager: ModelManager
  private let server: LlamaServer

  private var headerView: HeaderView?
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
  } onRebuild: { [weak self] in
    self?.rebuildCatalogSection()
  }

  private var isSettingsVisible = false
  private let observer = NotificationObserver()
  private weak var currentlyHighlightedView: ItemView?
  private var preservingHighlightForFamily: String?
  private var welcomePopover: WelcomePopover?

  init(modelManager: ModelManager? = nil, server: LlamaServer? = nil) {
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.modelManager = modelManager ?? .shared
    self.server = server ?? .shared
    super.init()
    configureStatusItem()
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
    addObservers()
  }

  func menuDidClose(_ menu: NSMenu) {
    guard menu === statusItem.menu else { return }
    currentlyHighlightedView?.setHighlight(false)
    currentlyHighlightedView = nil
    preservingHighlightForFamily = nil
    observer.removeAll()
    isSettingsVisible = false
    catalogSection.reset()
  }

  func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
    // Only manage highlights for enabled items in the root menu (family items, settings, footer).
    // Submenu model items remain disabled and use their own tracking areas for hover.
    // This optimization reduces highlight updates from O(n) to O(1) by tracking only the current view.
    guard menu === statusItem.menu else { return }
    let highlighted = item?.view as? ItemView

    // During catalog rebuilds, preserve the highlight on the family header being toggled
    // to avoid flicker when the old view is destroyed and the new one is created
    if preservingHighlightForFamily != nil && highlighted == nil {
      return
    }

    if currentlyHighlightedView !== highlighted {
      currentlyHighlightedView?.setHighlight(false)
      highlighted?.setHighlight(true)
      currentlyHighlightedView = highlighted
    }
  }

  // MARK: - Menu Construction

  private func rebuildMenu(_ menu: NSMenu) {
    menu.removeAllItems()

    let view = HeaderView(server: server)
    headerView = view
    menu.addItem(NSMenuItem.viewItem(with: view))
    menu.addItem(.separator())

    installedSection.add(to: menu)
    catalogSection.add(to: menu)
    addFooter(to: menu)

    if isSettingsVisible {
      menu.addItem(.separator())
      let rootView = SettingsView()
      let view = NSHostingView(rootView: rootView)
      let height = view.fittingSize.height
      view.frame = NSRect(x: 0, y: 0, width: Layout.menuWidth, height: height)
      let item = NSMenuItem.viewItem(with: view)
      menu.addItem(item)
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

  /// Called when family collapse/expand is toggled.
  /// Rebuilds only the catalog section to show/hide models while preserving collapse state.
  private func rebuildCatalogSection() {
    guard let menu = statusItem.menu else { return }

    // Remember which family header was highlighted before rebuilding
    let highlightedFamily = (currentlyHighlightedView as? FamilyHeaderView)?.family

    // Set flag to prevent unhighlighting during rebuild
    preservingHighlightForFamily = highlightedFamily

    catalogSection.rebuild(in: menu)

    // Re-highlight the family header if it was highlighted before rebuilding.
    // Use a short delay to let the menu system settle after the rebuild.
    guard let family = highlightedFamily else {
      preservingHighlightForFamily = nil
      return
    }

    DispatchQueue.main.async { [weak self] in
      guard let self, let currentMenu = self.statusItem.menu, currentMenu === menu else {
        self?.preservingHighlightForFamily = nil
        return
      }
      defer { self.preservingHighlightForFamily = nil }

      if let headerView = self.findFamilyHeader(for: family, in: currentMenu) {
        headerView.setHighlight(true)
        self.currentlyHighlightedView = headerView
      }
    }
  }

  /// Finds the FamilyHeaderView for a given family name in the menu.
  private func findFamilyHeader(for family: String, in menu: NSMenu) -> FamilyHeaderView? {
    menu.items.lazy.compactMap { $0.view as? FamilyHeaderView }
      .first { $0.family == family }
  }

  /// Helper to observe a notification and call refresh on the main actor
  private func observeAndRefresh(_ name: Notification.Name) {
    observer.observe(name) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refresh()
      }
    }
  }

  // Observe server and download changes while the menu is open.
  private func addObservers() {
    observer.removeAll()

    // Server started/stopped - update icon and views
    observeAndRefresh(.LBServerStateDidChange)

    // Server memory usage changed - update running model stats
    observeAndRefresh(.LBServerMemoryDidChange)

    // Download progress updated - refresh progress indicators
    observeAndRefresh(.LBModelDownloadsDidChange)

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

    headerView?.refresh()
    installedSection.refresh()
    catalogSection.refresh()
  }

  private func addFooter(to menu: NSMenu) {
    menu.addItem(.separator())

    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let appVersionText: String
    #if DEBUG
      // Debug builds show hammer emoji
      appVersionText = "🔨"
    #else
      appVersionText =
        AppInfo.shortVersion == "0.0.0"
        // Internal builds (0.0.0) show build number
        ? "build \(AppInfo.buildNumber)"
        // Public builds show marketing version
        : AppInfo.shortVersion
    #endif

    let versionButton = NSButton(title: "", target: self, action: #selector(checkForUpdates))
    versionButton.isBordered = false
    versionButton.translatesAutoresizingMaskIntoConstraints = false
    versionButton.lineBreakMode = .byTruncatingMiddle
    versionButton.attributedTitle = NSAttributedString(
      string: appVersionText,
      attributes: [
        .font: Typography.primary,
        .foregroundColor: NSColor.tertiaryLabelColor,
      ])
    (versionButton.cell as? NSButtonCell)?.highlightsBy = []

    let llamaCppLabel = Typography.makePrimaryLabel(" · llama.cpp \(AppInfo.llamaCppVersion)")
    llamaCppLabel.textColor = .tertiaryLabelColor
    llamaCppLabel.lineBreakMode = .byTruncatingMiddle
    llamaCppLabel.translatesAutoresizingMaskIntoConstraints = false

    let settingsButton = NSButton(
      title: "Settings", target: self, action: #selector(toggleSettings))
    settingsButton.font = Typography.secondary
    settingsButton.bezelStyle = .texturedRounded
    settingsButton.translatesAutoresizingMaskIntoConstraints = false
    settingsButton.keyEquivalent = ","

    let quitButton = NSButton(title: "Quit", target: self, action: #selector(quitApp))
    quitButton.font = Typography.secondary
    quitButton.bezelStyle = .texturedRounded
    quitButton.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(versionButton)
    container.addSubview(llamaCppLabel)
    container.addSubview(settingsButton)
    container.addSubview(quitButton)

    let horizontalPadding = Layout.outerHorizontalPadding + Layout.innerHorizontalPadding

    NSLayoutConstraint.activate([
      container.widthAnchor.constraint(equalToConstant: Layout.menuWidth),
      container.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
      versionButton.leadingAnchor.constraint(
        equalTo: container.leadingAnchor, constant: horizontalPadding),
      versionButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),

      llamaCppLabel.leadingAnchor.constraint(equalTo: versionButton.trailingAnchor),
      llamaCppLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

      settingsButton.trailingAnchor.constraint(
        equalTo: quitButton.leadingAnchor, constant: -8),
      settingsButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),

      quitButton.trailingAnchor.constraint(
        equalTo: container.trailingAnchor, constant: -horizontalPadding),
      quitButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),

      llamaCppLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: settingsButton.leadingAnchor, constant: -8),
    ])

    let item = NSMenuItem.viewItem(with: container)
    item.isEnabled = true
    menu.addItem(item)
  }

  @objc private func checkForUpdates() {
    NotificationCenter.default.post(name: .LBCheckForUpdates, object: nil)
  }

  @objc private func toggleSettings() {
    isSettingsVisible.toggle()
    if let menu = statusItem.menu {
      rebuildMenu(menu)
    }
  }

  @objc private func quitApp() {
    NSApplication.shared.terminate(nil)
  }
}
