import SwiftUI

/// Settings window controller -- manages the settings window lifecycle.
/// Uses SwiftUI for the content but AppKit for window management to ensure
/// proper behavior as a menu bar app (no dock icon, proper activation).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
  static let shared = SettingsWindowController()

  private var window: NSWindow?
  private var observer: NSObjectProtocol?

  private override init() {
    super.init()
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
      NSApp.setActivationPolicy(.regular)
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    // Create the SwiftUI content view
    let contentView = SettingsView()

    // Create the window
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Settings"
    window.contentView = NSHostingView(rootView: contentView)
    window.center()
    window.isReleasedWhenClosed = false
    window.delegate = self

    self.window = window

    // Show window and activate app
    NSApp.setActivationPolicy(.regular)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }
}

/// SwiftUI view for settings content.
struct SettingsView: View {
  @State private var launchAtLogin = LaunchAtLogin.isEnabled
  @State private var sleepIdleTime = UserSettings.sleepIdleTime

  var body: some View {
    Form {
      // Launch at login section
      Section {
        Toggle("Launch at login", isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { _, newValue in
            _ = LaunchAtLogin.setEnabled(newValue)
          }
      }

      // Sleep idle time section
      Section {
        VStack(alignment: .leading, spacing: 8) {
          LabeledContent("Unload when idle") {
            Picker("", selection: $sleepIdleTime) {
              ForEach(UserSettings.SleepIdleTime.allCases, id: \.self) { time in
                Text(time.displayName).tag(time)
              }
            }
            .labelsHidden()
            .fixedSize()
            .onChange(of: sleepIdleTime) { _, newValue in
              UserSettings.sleepIdleTime = newValue
            }
          }

          Text("Automatically unloads the model from memory when not in use.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 380)
    .fixedSize()
  }
}

#Preview {
  SettingsView()
}
