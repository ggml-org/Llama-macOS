import Carbon.HIToolbox
import SwiftUI

/// Display / conversion helpers for the hotkey combo. Lives here (with the
/// only UI that renders combos) rather than in GlobalHotkey.swift, which stays
/// a pure registration wrapper.
extension GlobalHotkey.Combo {
  /// Human-readable form, e.g. "⌥Space" or "⌃⇧K" -- modifier symbols in the
  /// canonical macOS order (⌃⌥⇧⌘) followed by the key's name.
  var displayString: String {
    var symbols = ""
    if modifiers & controlKey != 0 { symbols += "⌃" }
    if modifiers & optionKey != 0 { symbols += "⌥" }
    if modifiers & shiftKey != 0 { symbols += "⇧" }
    if modifiers & cmdKey != 0 { symbols += "⌘" }
    return symbols + Self.keyName(for: keyCode)
  }

  /// Builds a combo from an NSEvent keypress, translating AppKit modifier
  /// flags to the Carbon mask `RegisterEventHotKey` expects. Returns `nil`
  /// when the combo isn't usable as a global hotkey: it needs ⌘, ⌥, or ⌃
  /// (a bare key or shift-only combo would shadow normal typing everywhere).
  static func from(event: NSEvent) -> GlobalHotkey.Combo? {
    var mods = 0
    if event.modifierFlags.contains(.control) { mods |= controlKey }
    if event.modifierFlags.contains(.option) { mods |= optionKey }
    if event.modifierFlags.contains(.shift) { mods |= shiftKey }
    if event.modifierFlags.contains(.command) { mods |= cmdKey }
    guard mods & (cmdKey | optionKey | controlKey) != 0 else { return nil }
    return GlobalHotkey.Combo(keyCode: Int(event.keyCode), modifiers: mods)
  }

  /// Name for a virtual key code: named keys (Space, arrows, F-keys, ...)
  /// from a fixed table, character keys from the current keyboard layout.
  private static func keyName(for keyCode: Int) -> String {
    if let special = specialKeyNames[keyCode] { return special }
    return layoutKeyName(for: keyCode) ?? "Key \(keyCode)"
  }

  /// Keys whose layout translation is empty or unreadable (whitespace,
  /// control, navigation, function keys).
  private static let specialKeyNames: [Int: String] = [
    kVK_Space: "Space",
    kVK_Return: "↩",
    kVK_Tab: "⇥",
    kVK_Escape: "⎋",
    kVK_Delete: "⌫",
    kVK_ForwardDelete: "⌦",
    kVK_LeftArrow: "←",
    kVK_RightArrow: "→",
    kVK_UpArrow: "↑",
    kVK_DownArrow: "↓",
    kVK_Home: "↖",
    kVK_End: "↘",
    kVK_PageUp: "⇞",
    kVK_PageDown: "⇟",
    kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
    kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
    kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
  ]

  /// Translates a key code to its base character in the user's current
  /// keyboard layout (so e.g. the key that types ";" on QWERTY shows as "M"
  /// on AZERTY). Uppercased for display, matching how macOS renders shortcuts.
  private static func layoutKeyName(for keyCode: Int) -> String? {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
      let rawLayoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    let layoutData = Unmanaged<CFData>.fromOpaque(rawLayoutData).takeUnretainedValue() as Data

    var deadKeyState: UInt32 = 0
    var chars = [UniChar](repeating: 0, count: 4)
    var length = 0
    let status = layoutData.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> OSStatus in
      guard let layout = buf.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
        return OSStatus(paramErr)
      }
      return UCKeyTranslate(
        layout,
        UInt16(keyCode),
        UInt16(kUCKeyActionDisplay),
        0,  // no modifiers -- we want the key's base character
        UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysBit),
        &deadKeyState,
        chars.count,
        &length,
        &chars
      )
    }
    guard status == noErr, length > 0 else { return nil }
    let name = String(utf16CodeUnits: chars, count: length)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : name.uppercased()
  }
}

/// A button that records a key combo: click to arm, then press the desired
/// shortcut. While armed it swallows keystrokes via a local event monitor;
/// Escape (or clicking the button again) cancels. Combos without ⌘/⌥/⌃ are
/// ignored (they'd shadow normal typing system-wide).
///
/// Known quirk (prototype scope): the currently-registered hotkey is still
/// live while recording, so re-pressing the *current* combo toggles the
/// capture panel instead of recording -- harmless, since re-recording the
/// same combo would be a no-op anyway.
struct ShortcutRecorder: View {
  @Binding var combo: GlobalHotkey.Combo

  @State private var recording = false
  @State private var monitor: Any?

  var body: some View {
    Button {
      recording ? stopRecording() : startRecording()
    } label: {
      Text(recording ? "Press shortcut…" : combo.displayString)
        .foregroundStyle(recording ? .secondary : .primary)
    }
    .controlSize(.small)
    // If the row disappears mid-recording (window closed), drop the monitor.
    .onDisappear { stopRecording() }
  }

  private func startRecording() {
    recording = true
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if event.keyCode == UInt16(kVK_Escape), event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
        stopRecording()
        return nil
      }
      if let newCombo = GlobalHotkey.Combo.from(event: event) {
        combo = newCombo
        stopRecording()
        return nil
      }
      // Modifierless keystroke -- not a valid global shortcut; swallow it and
      // keep listening.
      return nil
    }
  }

  private func stopRecording() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    recording = false
  }
}
