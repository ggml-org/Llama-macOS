import LaunchAtLogin
import SwiftUI

struct SettingsView: View {
  @State private var launchAtLogin = LaunchAtLogin.isEnabled
  @State private var showQuantizedVariants = UserSettings.showQuantizedVariants

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Launch at Login")
        Spacer()
        Toggle("", isOn: $launchAtLogin)
          .labelsHidden()
          .toggleStyle(SwitchToggleStyle())
          .controlSize(.mini)
          .onChange(of: launchAtLogin) { _, newValue in
            LaunchAtLogin.isEnabled = newValue
          }
      }
      HStack {
        Text("Show quantized models")
        Spacer()
        Toggle("", isOn: $showQuantizedVariants)
          .labelsHidden()
          .toggleStyle(SwitchToggleStyle())
          .controlSize(.mini)
          .onChange(of: showQuantizedVariants) { _, newValue in
            UserSettings.showQuantizedVariants = newValue
          }
      }
    }
    .padding(EdgeInsets(top: 8, leading: 13, bottom: 8, trailing: 13))
  }
}

#Preview {
  SettingsView()
}
