import Foundation

/// On-disk record for a deeplink install that's been accepted but not yet
/// completed. We persist just the user-visible descriptor — `(repo, quant)` —
/// not the commit hash / blob SHAs / file list. Those can change server-side
/// between sessions (HF re-uploads, quant replaced), and re-resolving on
/// relaunch is cheap and catches that drift.
struct PendingInstallDescriptor: Codable, Equatable {
  /// Stable sideloaded id — `"{org}/{repo}:{QUANT}"`.
  let modelId: String
  /// HF repo in `"{org}/{repo}"` form, as originally parsed from the URL.
  let repo: String
  /// Canonical quant label. Never nil at persist time — by the time we persist,
  /// we've already picked a specific file (default or explicit).
  let quant: String
}

/// Persistence for pending deeplink installs. Stored in `UserDefaults` under
/// the `pendingInstalls` key as a JSON array of descriptors. Writing on every
/// add/remove is safe — descriptors are tiny and we don't expect more than a
/// handful at a time.
enum PendingInstallStore {
  private static let key = "pendingInstalls"

  static func load() -> [PendingInstallDescriptor] {
    guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
    return (try? JSONDecoder().decode([PendingInstallDescriptor].self, from: data)) ?? []
  }

  static func save(_ descriptors: [PendingInstallDescriptor]) {
    guard let data = try? JSONEncoder().encode(descriptors) else { return }
    UserDefaults.standard.set(data, forKey: key)
  }

  static func upsert(_ descriptor: PendingInstallDescriptor) {
    var all = load()
    all.removeAll { $0.modelId == descriptor.modelId }
    all.append(descriptor)
    save(all)
  }

  static func remove(modelId: String) {
    var all = load()
    all.removeAll { $0.modelId == modelId }
    save(all)
  }
}
