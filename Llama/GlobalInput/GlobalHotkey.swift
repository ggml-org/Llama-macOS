import AppKit
import Carbon.HIToolbox

/// A single system-wide hotkey, registered via Carbon's `RegisterEventHotKey`.
///
/// We use Carbon directly rather than pulling in a package: `RegisterEventHotKey`
/// is still the only real system-wide hotkey API, needs no Accessibility
/// permission or entitlement, is sandbox/App-Store safe, and only delivers the
/// specific combo we register (unlike an `NSEvent` global monitor, which sees
/// every keystroke and needs Accessibility). It's a Carbon API and nominally
/// deprecated, but it's what Spotlight-alikes (and Electron/VS Code/Slack) use.
///
/// Lifetime: keep a strong reference for as long as the hotkey should be live;
/// `deinit` unregisters. Prototype scope -- one hotkey, fixed at construction.
final class GlobalHotkey {
  /// A key + modifier combo. `keyCode` is a virtual key code (`kVK_*`);
  /// `modifiers` is a Carbon modifier mask (`cmdKey`, `optionKey`, ...).
  struct Combo: Equatable {
    let keyCode: Int
    let modifiers: Int

    /// ⌥Space -- Raycast's default. A key+modifier combo (not modifier-only),
    /// so it sidesteps the macOS 15 regression where Option-only hotkeys break.
    static let optionSpace = Combo(keyCode: kVK_Space, modifiers: optionKey)
  }

  private var hotKeyRef: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?
  private let handler: () -> Void

  /// A process-unique id so the C event callback can find the right instance.
  private static var nextId: UInt32 = 1
  private static var instances: [UInt32: GlobalHotkey] = [:]
  private let id: UInt32

  /// Registers `combo` system-wide. `handler` runs on the main thread each time
  /// the combo is pressed. Returns `nil` if registration fails (e.g. the combo
  /// is already claimed by another app).
  init?(combo: Combo, handler: @escaping () -> Void) {
    self.handler = handler
    self.id = GlobalHotkey.nextId
    GlobalHotkey.nextId += 1

    // Install one app-wide Carbon handler for hot-key-pressed events. Carbon
    // dispatches all registered hotkeys through this single callback; we route
    // to the right instance by the `id` stored in the EventHotKeyID.
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: OSType(kEventHotKeyPressed)
    )
    let installStatus = InstallEventHandler(
      GetEventDispatcherTarget(),
      { _, event, _ -> OSStatus in
        var hotKeyId = EventHotKeyID()
        GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyId
        )
        if let instance = GlobalHotkey.instances[hotKeyId.id] {
          instance.handler()
        }
        return noErr
      },
      1,
      &eventType,
      nil,
      &eventHandler
    )
    guard installStatus == noErr else { return nil }

    // Register the actual combo. The signature is an arbitrary 4-char tag Carbon
    // uses to namespace hotkey ids; the id is what our callback matches on.
    let signature = OSType(0x4C_4C_4D_42)  // 'LLMB'
    let hotKeyId = EventHotKeyID(signature: signature, id: id)
    let registerStatus = RegisterEventHotKey(
      UInt32(combo.keyCode),
      UInt32(combo.modifiers),
      hotKeyId,
      GetEventDispatcherTarget(),
      0,
      &hotKeyRef
    )
    guard registerStatus == noErr else {
      if let eventHandler { RemoveEventHandler(eventHandler) }
      return nil
    }

    GlobalHotkey.instances[id] = self
  }

  deinit {
    if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    if let eventHandler { RemoveEventHandler(eventHandler) }
    GlobalHotkey.instances[id] = nil
  }
}
