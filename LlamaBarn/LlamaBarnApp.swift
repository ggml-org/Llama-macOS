import AppKit
import Sentry
import Sparkle
import SwiftUI
import os.log

@main
struct LlamaBarnApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    // Empty scene, as we are a menu bar app
    Settings {
      EmptyView()
    }
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings...") {
          NotificationCenter.default.post(name: .LBShowSettings, object: nil)
        }
        .keyboardShortcut(",")
      }
    }
  }
}

class AppDelegate: NSObject, NSApplicationDelegate {
  private var updaterController: SPUStandardUpdaterController?
  private let logger = Logger(subsystem: Logging.subsystem, category: "AppDelegate")
  private var menuController: MenuController?
  private var settingsWindowController: SettingsWindowController?
  private var updatesObserver: NSObjectProtocol?

  // Deeplink (llamabarn://) plumbing.
  // Cold-launch URL events arrive before `applicationDidFinishLaunching`, so we have
  // to register the Apple-event handler in `applicationWillFinishLaunching`. The app's
  // menu/ModelManager/alert infra isn't ready yet at that point, so the handler just
  // enqueues — the queue drains once full setup completes.
  private var pendingURLs: [URL] = []
  private var didBootstrap = false

  func applicationWillFinishLaunching(_ notification: Notification) {
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
      forEventClass: AEEventClass(kInternetEventClass),
      andEventID: AEEventID(kAEGetURL)
    )
  }

  @MainActor
  @objc func handleGetURLEvent(
    _ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor
  ) {
    guard
      let str = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
      let url = URL(string: str)
    else { return }

    if didBootstrap {
      DeeplinkHandler.shared.handle(url: url)
    } else {
      pendingURLs.append(url)
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Enable visual debugging if LB_DEBUG_UI is set
    NSView.swizzleDebugBehavior()

    // Initialize Sentry for error reporting (release builds only)
    #if !DEBUG
      SentrySDK.start { options in
        options.dsn =
          "https://9a490c1c8715f73a0db5f65890165602@o509420.ingest.us.sentry.io/4510221602914304"
        options.debug = false
        options.releaseName = AppInfo.shortVersion
        options.environment = AppInfo.shortVersion == "0.0.0" ? "internal" : "production"

        // Disable Sentry's auto-instrumented HTTP client error capture. ModelManager
        // already captures Hugging Face failures manually with richer context
        // (modelId, url), and the auto-instrumentation fires repeatedly per logical
        // failure (e.g. range request retries) creating large amounts of duplicate
        // noise. We have no other external HTTP endpoints worth auto-capturing.
        options.enableCaptureFailedRequests = false

        // Filter out non-actionable network errors globally so they don't use up quota
        options.beforeSend = { event in
          if let error = event.error as NSError? {
            let ignoredCodes = [
              NSURLErrorCancelled,
              NSURLErrorNotConnectedToInternet,
              NSURLErrorNetworkConnectionLost,
            ]
            if error.domain == NSURLErrorDomain && ignoredCodes.contains(error.code) {
              return nil  // Drop this event
            }
          }
          return event
        }
      }
    #endif

    logger.info("LlamaBarn starting up")

    // Configure app as menu bar only (removes from Dock)
    NSApp.setActivationPolicy(.accessory)

    // Set up automatic updates using Sparkle framework
    // Skip starting the updater for debug builds to avoid false update prompts
    #if DEBUG
      let startUpdater = false
    #else
      let startUpdater = true
    #endif
    updaterController = SPUStandardUpdaterController(
      startingUpdater: startUpdater,
      // Capture errors and events for logging/troubleshooting
      updaterDelegate: self,
      // Use our custom UI handling for gentle reminders
      userDriverDelegate: self
    )

    // Initialize the shared model library manager to scan for existing models
    _ = ModelManager.shared

    // Create the AppKit-based status bar menu (installed models only for now)
    menuController = MenuController()
    DeeplinkHandler.shared.menuController = menuController

    // Initialize settings window controller (listens for LBShowSettings notifications)
    settingsWindowController = SettingsWindowController.shared

    // Start the server in Router Mode
    LlamaServer.shared.start()

    // Listen for explicit update requests from the menu controller
    updatesObserver = NotificationCenter.default.addObserver(
      forName: .LBCheckForUpdates, object: nil, queue: .main
    ) { [weak self] _ in
      self?.updaterController?.checkForUpdates(nil)
    }

    #if DEBUG
      // Auto-open menu in debug builds to save a click
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.menuController?.openMenu()
      }
    #endif

    // Drain any llamabarn:// URLs that arrived during cold-launch before the rest
    // of the app was ready.
    didBootstrap = true
    let queued = pendingURLs
    pendingURLs.removeAll()
    for url in queued {
      DeeplinkHandler.shared.handle(url: url)
    }

    logger.info("LlamaBarn startup complete")
  }

  func applicationWillTerminate(_ notification: Notification) {
    logger.info("LlamaBarn shutting down")

    // Gracefully stop the llama-server process when app quits
    LlamaServer.shared.stop()

    // Clean up observers
    if let updatesObserver { NotificationCenter.default.removeObserver(updatesObserver) }
  }
}

// MARK: - SPUStandardUserDriverDelegate

extension AppDelegate: SPUStandardUserDriverDelegate {
  // Tells Sparkle this app supports gentle reminders for background update checks.
  // This prevents intrusive modal dialogs and allows us to show dock badges instead.
  var supportsGentleScheduledUpdateReminders: Bool {
    true
  }

  // Called when Sparkle is about to show an update dialog.
  // We use this to switch from menu bar mode to dock app mode so the dialog appears properly.
  func standardUserDriverWillHandleShowingUpdate(
    _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
  ) {
    // Always show in dock when update dialog will appear
    NSApp.setActivationPolicy(.regular)
  }

  // Called when the update process is completely finished (installed, skipped, or dismissed).
  // We use this to return the app to menu bar mode.
  func standardUserDriverWillFinishUpdateSession() {
    // Return to menu bar mode
    NSApp.setActivationPolicy(.accessory)
  }
}

// MARK: - SPUUpdaterDelegate

extension AppDelegate: SPUUpdaterDelegate {
  func updater(_ updater: SPUUpdater, didFailToCheckForUpdatesWithError error: Error) {
    logger.error(
      "Sparkle: failed to check for updates: \(error.localizedDescription, privacy: .public)")
  }
}
