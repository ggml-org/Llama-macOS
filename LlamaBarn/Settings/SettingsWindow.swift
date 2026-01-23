import SwiftUI

/// Settings window controller -- manages the settings window lifecycle.
/// Uses SwiftUI for the content but AppKit for window management to ensure
/// proper behavior as a menu bar app (no dock icon, proper activation).
@MainActor
final class SettingsWindowController {
  static let shared = SettingsWindowController()

  private var window: NSWindow?
  private var observer: NSObjectProtocol?

  private init() {
    // Listen for settings show requests
    observer = NotificationCenter.default.addObserver(
      forName: .LBShowSettings, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.showSettings()
      }
    }
  }

  func showSettings() {
    // If window exists, just bring it to front
    if let window, window.isVisible {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    // Create the SwiftUI content view
    let contentView = SettingsView()

    // Create the window
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 340, height: 280),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Settings"
    window.contentView = NSHostingView(rootView: contentView)
    window.center()
    window.isReleasedWhenClosed = false

    self.window = window

    // Show window and activate app
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

/// SwiftUI view for settings content.
struct SettingsView: View {
  @State private var launchAtLogin = LaunchAtLogin.isEnabled
  @State private var contextWindow = UserSettings.defaultContextWindow
  @State private var sleepIdleTime = UserSettings.sleepIdleTime

  var body: some View {
    Form {
      // Launch at login toggle
      Toggle("Launch at login", isOn: $launchAtLogin)
        .onChange(of: launchAtLogin) { _, newValue in
          _ = LaunchAtLogin.setEnabled(newValue)
        }

      Divider()

      // Context length picker
      VStack(alignment: .leading, spacing: 4) {
        Picker("Context length", selection: $contextWindow) {
          ForEach(UserSettings.ContextWindowSize.allCases, id: \.self) { size in
            Text(size.displayName).tag(size)
          }
        }
        .pickerStyle(.segmented)
        .onChange(of: contextWindow) { _, newValue in
          UserSettings.defaultContextWindow = newValue
        }

        Text(contextInfoText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Divider()

      // Sleep idle time picker
      VStack(alignment: .leading, spacing: 4) {
        Picker("Unload when idle", selection: $sleepIdleTime) {
          ForEach(UserSettings.SleepIdleTime.allCases, id: \.self) { time in
            Text(time.displayName).tag(time)
          }
        }
        .pickerStyle(.segmented)
        .onChange(of: sleepIdleTime) { _, newValue in
          UserSettings.sleepIdleTime = newValue
        }

        Text("Automatically unloads the model from memory when not in use.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 340)
    .fixedSize()
  }

  /// Builds the context length info text, including memory budget if available.
  private var contextInfoText: String {
    let sysMemMb = SystemMemory.memoryMb
    guard sysMemMb > 0 else {
      return
        "Higher context lengths use more memory. The app may reduce the context length to stay within a safe memory budget."
    }

    let budgetMb = CatalogEntry.memoryBudget(systemMemoryMb: sysMemMb)
    let budgetGbRounded = Int((budgetMb / 1024.0).rounded())

    return
      "Higher context lengths use more memory. The app may reduce the context length to stay within a safe memory budget: \(budgetGbRounded) GB on this Mac."
  }
}
