import AppKit
import Sparkle
import SwiftUI
import os.log

@main
struct LlamaBarnApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    Settings { SettingsView() }
  }
}

class AppDelegate: NSObject, NSApplicationDelegate {
  private var updaterController: SPUStandardUpdaterController?
  private let logger = Logger(subsystem: "LlamaBarn", category: "AppDelegate")
  private var menuController: AppMenuController?
  private var updatesObserver: NSObjectProtocol?

  func applicationDidFinishLaunching(_ notification: Notification) {
    logger.info("LlamaBarn starting up")

    // Configure app as menu bar only (removes from Dock)
    NSApp.setActivationPolicy(.accessory)

    // Set up automatic updates using Sparkle framework
    updaterController = SPUStandardUpdaterController(
      // Begin automatic update checking immediately
      startingUpdater: true,
      // Capture errors and events for logging/troubleshooting
      updaterDelegate: self,
      // Use our custom UI handling for gentle reminders
      userDriverDelegate: self
    )

    // Check for updates on app launch (in addition to automatic hourly checks)
    #if !DEBUG
      updaterController?.updater.checkForUpdatesInBackground()
    #endif

    // Initialize the shared model library manager to scan for existing models
    _ = ModelManager.shared

    // Create the AppKit-based status bar menu (installed models only for now)
    menuController = AppMenuController()

    // Listen for explicit update requests from the menu controller
    updatesObserver = NotificationCenter.default.addObserver(
      forName: .LBCheckForUpdates, object: nil, queue: .main
    ) { [weak self] _ in
      self?.updaterController?.updater.checkForUpdates()
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
    return true
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
    logger.error("Sparkle: failed to check updates: \(error.localizedDescription, privacy: .public)")
  }
}

// MARK: - Notifications

extension Notification.Name {
  static let LBCheckForUpdates = Notification.Name("LBCheckForUpdates")
}
