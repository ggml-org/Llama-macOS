import LaunchAtLogin
import SwiftUI

struct SettingsView: View {
  @State private var launchAtLogin = LaunchAtLogin.isEnabled

  private let versionSummary = "v\(AppInfo.shortVersion) · build \(AppInfo.buildNumber) · llama.cpp \(AppInfo.llamaCppVersion)"

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 12) {
        Toggle("Launch at Login", isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { _, newValue in
            LaunchAtLogin.isEnabled = newValue
          }
        Button("Check for Updates…") {
          NotificationCenter.default.post(name: .LBCheckForUpdates, object: nil)
        }
      }

      Divider()

      VStack(alignment: .leading, spacing: 4) {
        Text(versionSummary)
          .font(.callout)
          .foregroundStyle(.secondary)
        #if DEBUG
          Text(SystemMemory.formatMemory())
            .font(.callout)
            .foregroundStyle(.secondary)
        #endif
      }
    }
    .onAppear {
      launchAtLogin = LaunchAtLogin.isEnabled
    }
    .padding(24)
    .frame(minWidth: 360)
  }
}

#Preview {
  SettingsView()
}
