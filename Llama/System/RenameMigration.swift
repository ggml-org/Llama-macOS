import Foundation
import os.log

/// One-time migration from the LlamaBarn identity to the Llama identity.
///
/// The 0.32 release renames the app and its bundle id
/// (`app.llamabarn.LlamaBarn[.dev]` → `app.llama.Llama[.dev]`). macOS keys
/// UserDefaults (and other per-app state) by bundle id, so a bare rename would
/// strand every existing user's settings -- HF cache dir, HF token, context-tier
/// picks, Sparkle's own update state -- under the old domain, presenting as a
/// factory-fresh app. This copies that state into the new domain on first launch.
///
/// Call `runIfNeeded()` before anything reads settings or scans the cache (top
/// of `applicationDidFinishLaunching`). It's idempotent: a flag in the new
/// domain gates it, so it runs exactly once and is a cheap no-op after. The old
/// domain is left intact (not deleted) so a downgrade still finds its data.
enum RenameMigration {
  private static let logger = Logger(subsystem: Logging.subsystem, category: "RenameMigration")

  /// Set in the *new* domain once migration completes; gates re-runs.
  private static let completedKey = "renameMigrationCompleted"

  /// Bundle-id prefix of the pre-rename identity.
  private static let oldProductName = "app.llamabarn.LlamaBarn"

  static func runIfNeeded() {
    let defaults = UserDefaults.standard

    guard let current = Bundle.main.bundleIdentifier else { return }
    let old = oldDomain(forCurrent: current)

    // Still running under the old identity -- either this helper shipped ahead of
    // the bundle-id flip, or it's a dev build that hasn't flipped yet. There's
    // nothing to migrate (old domain == current domain), and crucially we must
    // not burn the one-shot flag now, or the real migration would be skipped once
    // the rename lands.
    guard current != old else { return }

    guard !defaults.bool(forKey: completedKey) else { return }

    migrateUserDefaults(from: old, into: defaults)
    migratePartialDir()

    defaults.set(true, forKey: completedKey)
    logger.info("Rename migration complete")
  }

  /// The pre-rename bundle id whose UserDefaults domain we read from, derived
  /// from the current (post-rename) bundle id so dev and production each pull
  /// from their own old domain.
  /// e.g. `app.llama.Llama.dev` → `app.llamabarn.LlamaBarn.dev`.
  private static func oldDomain(forCurrent current: String) -> String {
    current.hasSuffix(".dev") ? "\(oldProductName).dev" : oldProductName
  }

  // MARK: - UserDefaults

  /// Copies every persisted key from the old domain into the new one, without
  /// clobbering anything the new app has already written this launch. Pulls the
  /// whole domain (rather than an allowlist) so it also carries keys we don't own
  /// -- Sparkle's update-group/last-check state, window frames -- and any settings
  /// added in future releases, with no per-key maintenance.
  private static func migrateUserDefaults(from oldDomain: String, into defaults: UserDefaults) {
    guard let old = defaults.persistentDomain(forName: oldDomain), !old.isEmpty else { return }

    var migrated = 0
    for (key, value) in old where defaults.object(forKey: key) == nil {
      defaults.set(value, forKey: key)
      migrated += 1
    }
    logger.info(
      "Migrated \(migrated) UserDefaults keys from \(oldDomain, privacy: .public)")
  }

  // MARK: - On-disk staging dir

  /// Renames the download-staging dir from the old `.llamabarn-partial` to the
  /// new `.llama-partial`, preserving any in-flight (paused) downloads so they
  /// still resume after the update. Best-effort: no-op if there's nothing to move
  /// or the new dir already exists.
  ///
  /// Runs after the UserDefaults migration so a customized HF cache location is
  /// already in place when we resolve `hfCacheDirectory`.
  private static func migratePartialDir() {
    let fm = FileManager.default
    let cacheDir = UserSettings.hfCacheDirectory
    let old = cacheDir.appendingPathComponent(".llamabarn-partial")
    let new = cacheDir.appendingPathComponent(HFCache.partialRootDirName)

    guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
    do {
      try fm.moveItem(at: old, to: new)
      logger.info(
        "Migrated partial-download dir to \(HFCache.partialRootDirName, privacy: .public)")
    } catch {
      logger.error(
        "Failed to migrate partial-download dir: \(error.localizedDescription, privacy: .public)")
    }
  }
}
