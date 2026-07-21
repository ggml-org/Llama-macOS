import AppKit
import SwiftUI
import os.log

/// Owns the global-input feature: the system-wide hotkey, the floating capture
/// panel, and the dispatch of a captured prompt to the web UI.
///
/// Prototype scope: fixed hotkey (⌥Space), single panel reused across
/// invocations, opens the web UI on submit. Hold a strong reference (AppDelegate
/// does) for the hotkey to stay registered.
@MainActor
final class GlobalInputController {
  private let logger = Logger(subsystem: Logging.subsystem, category: "GlobalInput")
  private var hotkey: GlobalHotkey?
  private var panel: CapturePanel?

  init() {
    // Registration can fail if the combo is already claimed; log and continue
    // (the feature is just inert rather than crashing the app).
    hotkey = GlobalHotkey(combo: .optionSpace) { [weak self] in
      Task { @MainActor in self?.toggle() }
    }
    if hotkey == nil {
      logger.error("Failed to register global hotkey (⌥Space) -- may be in use")
    }
  }

  /// Show the panel, unconditionally. Used by the DEBUG auto-open to bring up
  /// the capture panel on launch (see LlamaApp).
  func show() {
    present()
  }

  /// Show the panel if hidden, hide it if already visible (pressing the hotkey
  /// again is a natural dismiss).
  private func toggle() {
    if let panel, panel.isVisible {
      dismiss()
    } else {
      present()
    }
  }

  private func present() {
    // Rebuild content each time so the model chip reflects the current installed
    // set and resolved default (both can change between invocations).
    // Pretty names, same parsed rendering as the menu's rows; tags shown only
    // when two rows would otherwise render identically (same rule as the menu).
    let downloaded = ModelManager.shared.downloadedModels
    var keyCounts = [String: Int]()
    for model in downloaded {
      keyCounts[ModelIdParser.displayKey(model.id), default: 0] += 1
    }
    var models = downloaded.map { model -> CaptureModel in
      let parsed = ModelIdParser.parse(model.id)
      var name = (parsed.displayOrg.map { $0 + "/" } ?? "") + parsed.name
      if keyCounts[ModelIdParser.displayKey(model.id), default: 0] > 1, !parsed.tags.isEmpty {
        name += " " + parsed.tags.joined(separator: " ")
      }
      return CaptureModel(id: model.id, name: name, params: parsed.params, quant: parsed.quant)
    }
    let defaultId = resolveModelId()
    // Order the selector most-recently-used first, so the model you'll most
    // likely pick (typically the current one) sits under the cursor when the
    // selector opens. Ties -- including every never-run model, which all read 0
    // -- keep their installed order via the enumerated offset, since Swift's
    // `sort` isn't stable.
    models = models.enumerated().sorted { a, b in
      let da = UserSettings.modelLastUsed(for: a.element.id)
      let db = UserSettings.modelLastUsed(for: b.element.id)
      return da == db ? a.offset < b.offset : da > db
    }.map(\.element)
    let startIndex = models.firstIndex { $0.id == defaultId } ?? 0

    let panel = panel ?? makePanel()
    self.panel = panel
    installContent(in: panel, models: models, startIndex: startIndex)

    positionPanel(panel)

    // Bring our app forward just enough to give the panel key focus. Because the
    // panel is non-activating, this doesn't steal the user's app on dismiss.
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  private func dismiss() {
    panel?.orderOut(nil)
    // Return the user to whatever app was in front before we appeared.
    NSApp.hide(nil)
  }

  /// Build the panel chrome (frosted background, rounded corners). Content is
  /// (re)installed per presentation by `installContent`.
  private func makePanel() -> CapturePanel {
    let width: CGFloat = 640
    let panel = CapturePanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 64))
    panel.onResignKey = { [weak self] in self?.dismiss() }
    return panel
  }

  /// Swap in a fresh SwiftUI capture view for the current model set. The view
  /// reports its desired height via `onHeightChange` (the model picker makes it
  /// taller), and we resize/reposition the panel to match.
  private func installContent(in panel: CapturePanel, models: [CaptureModel], startIndex: Int) {
    let root = CaptureView(
      models: models,
      startIndex: startIndex,
      onSubmit: { [weak self] prompt, model in self?.submit(prompt, model: model) },
      onCancel: { [weak self] in self?.dismiss() },
      onHeightChange: { [weak self] height in self?.resize(panel, toContentHeight: height) }
    )
    // Host the SwiftUI cards directly on the clear panel. Each card draws its own
    // frosted material + rounded corners, so the input and the model selector
    // read as two separate panels (with a transparent gap between them). The
    // window shadow follows each card's opaque shape.
    panel.contentView = NSHostingView(rootView: root)
  }

  /// Screen y of the panel's top edge -- fixed so the panel grows downward (not
  /// upward) when the picker resizes it. Set by `positionPanel`.
  private var panelTopY: CGFloat = 0

  /// Center horizontally, anchor the top edge in the upper third of the active
  /// screen -- the spot Spotlight/Raycast use.
  private func positionPanel(_ panel: CapturePanel) {
    guard let screen = NSScreen.main else { return }
    let frame = screen.visibleFrame
    let size = panel.frame.size
    panelTopY = frame.minY + frame.height * 0.78
    let x = frame.midX - size.width / 2
    panel.setFrameOrigin(NSPoint(x: x, y: panelTopY - size.height))
  }

  /// Resize the panel to the content height the SwiftUI view reports, keeping the
  /// top edge fixed at `panelTopY` so it expands downward.
  private func resize(_ panel: CapturePanel, toContentHeight height: CGFloat) {
    guard abs(panel.frame.height - height) > 0.5 else { return }
    var frame = panel.frame
    frame.origin.y = panelTopY - height
    frame.size.height = height
    panel.setFrame(frame, display: true, animate: false)
    // Cards changed shape -- recompute the window shadow around them.
    panel.invalidateShadow()
  }

  /// Dispatch the captured prompt to the web UI.
  ///
  /// The llama.cpp WebUI reads `?q=` -- it opens a new conversation, prefills the
  /// message, and auto-sends it. Auto-send needs a model, so we also pass
  /// `?model=` when we can resolve one (the WebUI selects it via
  /// `findModelByName`, matching what the server's `/v1/models` exposes -- the
  /// same value as `model.id`).
  private func submit(_ prompt: String, model: CaptureModel?) {
    dismiss()

    // No model chosen means no models are installed -- a capture has nowhere to
    // go. Route to onboarding (pop the menu, which surfaces setup / model
    // browsing) rather than firing a send that can only fail.
    guard let model else {
      logger.info("Capture with no models installed -- routing to onboarding")
      NotificationCenter.default.post(name: .LBOpenMenu, object: nil)
      return
    }

    // Launching a prompt at a model is a deliberate use -- record it as
    // last-used (which also stamps the recency timestamp that orders the
    // selector), just like loading a model from the menu does. Without this,
    // capturing to a model never updates recency, since the panel dispatches to
    // the WebUI by URL rather than going through LlamaServer.loadModel.
    UserSettings.lastUsedModelId = model.id

    let host = LlamaServer.resolvedHost
    var components = URLComponents()
    components.scheme = "http"
    components.host = host
    components.port = LlamaServer.port
    components.path = "/"
    // Always pass a concrete `?model=`. Handing the WebUI `?q=` with no model is
    // a dead path: its auto-send has no "pick a model first" fallback, so it
    // either 400s or spins on "Loading models…" forever.
    components.queryItems = [
      URLQueryItem(name: "q", value: prompt),
      URLQueryItem(name: "model", value: model.id),
    ]

    guard let url = components.url else {
      logger.error("Failed to build web UI URL for captured prompt")
      return
    }

    logger.info("Dispatching captured prompt to \(url.absoluteString, privacy: .public)")
    NSWorkspace.shared.open(url)
  }

  /// Resolve which model the chip should open on, preferring the stickiest
  /// signal. Always returns a concrete id (just the default chip selection; the
  /// user can change it via the ⌘K menu). Assumes at least one model is installed.
  private func resolveModelId() -> String {
    let installed = ModelManager.shared.downloadedModels
    let installedIds = Set(installed.map(\.id))

    // 1. The last model the user deliberately ran -- if it's still installed.
    if let last = UserSettings.lastUsedModelId, installedIds.contains(last) {
      return last
    }
    // 2. Whatever is loaded right now.
    if let active = LlamaServer.shared.activeModelId, installedIds.contains(active) {
      return active
    }
    // 3. No history and nothing loaded (fresh install / cleared prefs): fall
    //    back to the smallest installed model -- fastest to load and respond,
    //    the safest default for a quick capture. The `?? ""` only bites when no
    //    models are installed at all; the empty id simply matches no row, so the
    //    panel opens on its first entry.
    return installed.min(by: { $0.fileSize < $1.fileSize })?.id ?? ""
  }
}
