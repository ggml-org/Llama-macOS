import Foundation

/// Manages notification observers with automatic cleanup.
/// Eliminates boilerplate for adding/removing NotificationCenter observers.
final class NotificationObserver {
  private var tokens: [NSObjectProtocol] = []

  /// Adds an observer for the specified notification name.
  func observe(
    _ name: Notification.Name, object: Any? = nil, using block: @escaping (Notification) -> Void
  ) {
    let token = NotificationCenter.default.addObserver(
      forName: name,
      object: object,
      queue: .main,
      using: block
    )
    tokens.append(token)
  }

  /// Removes all registered observers.
  func removeAll() {
    tokens.forEach { NotificationCenter.default.removeObserver($0) }
    tokens.removeAll()
  }

  deinit {
    tokens.forEach { NotificationCenter.default.removeObserver($0) }
  }
}
