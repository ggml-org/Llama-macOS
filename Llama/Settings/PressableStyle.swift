import SwiftUI

/// The app-wide button style for chrome-less clickables: text links, pill
/// segments, icon buttons, clickable rows. Renders the label bare (like
/// `.plain`) but dims it while the mouse is down, giving custom controls the
/// same pressed feedback native bezel buttons get from AppKit -- `.plain`
/// itself leaves custom labels visually inert.
struct PressableStyle: ButtonStyle {
  /// How far the label dims on mouse-down -- the one pressed-state constant,
  /// shared by every adopter.
  private static let pressedOpacity = 0.75

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
  }
}
