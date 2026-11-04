import Foundation
import os.log

/// Resolves the `llama` executable the app drives, and classifies whether the
/// app may update it.
///
/// Lookup order:
/// - a copy `install.sh` put on PATH (`~/.local/bin/llama`, a real file) at or
///   above `targetVersion` -- the user's own CLI, so the app runs the same
///   build they get in a terminal
/// - the app's own binary (`~/.llama-app/llama`), which it installs and keeps
///   at `targetVersion`
/// - Homebrew (or any other install in its bin dirs)
///
/// Only the app's own binary is managed (updated by the app); everything else
/// is used as-is and never modified.
///
/// The `install.sh` copy has to be at least the pinned build because
/// `install.sh` has no update mechanism -- unlike Homebrew, nobody runs a
/// routine upgrade on it -- so using it unconditionally would leave the app on
/// whatever build the user installed, for good. An older copy (or one whose
/// version can't be read, e.g. a broken binary) is skipped instead, and the app
/// falls back to its own pinned build. A newer one is used as-is: `install.sh`
/// always installs the bucket's latest, which is usually ahead of the pin.
///
/// `install.sh` used to symlink `~/.local/bin/llama` to `~/.llama-app/llama`,
/// so the two were one file. It now copies the binary instead, and rewrites
/// `~/.llama-app` on every run. Checking the copy first is what keeps the two
/// from fighting: while a current one exists, the app never uses `~/.llama-app`.
///
/// `llama` is the unified llama.cpp executable -- the server is `llama serve`
/// and memory profiling is `llama fit-params`, both subcommands of this one
/// binary. There is no separate `llama-server` / `llama-fit-params` to find.
enum LlamaBinaries {

  private static let logger = Logger(subsystem: Logging.subsystem, category: "LlamaBinaries")

  /// Where the app installs and keeps its own binary. The same folder
  /// `install.sh` downloads into, which is harmless: when `install.sh` has run,
  /// its copy on PATH wins and this path goes unused -- unless that copy falls
  /// behind the pin, in which case the app falls back here and updates it.
  static let managedPath: String =
    (NSHomeDirectory() as NSString).appendingPathComponent(".llama-app/llama")

  /// The `llama` on PATH. Either a real file (a copy from `install.sh`, which
  /// the app uses first) or a symlink (the one the app creates to its own
  /// binary, or one left by an older `install.sh`), which the app skips.
  static let pathEntry: String =
    (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/llama")

  /// Unmanaged locations to probe when the app hasn't installed its own binary.
  /// Covers the Homebrew bin dirs (Apple Silicon and Intel).
  private static let unmanagedDirs = ExecutableSearchPath.homebrewDirectories

  /// The build the app installs and keeps its own binary at -- the pinned
  /// target, not whatever is newest. Bump per app release after smoke-testing
  /// `serve` + `fit-params`; the app's auto-updater then rolls it out.
  static let targetVersion = LlamaVersion(parsing: "b11941")!

  /// The minimum build the app accepts from an unmanaged install (e.g. Homebrew)
  /// before nudging the user to update -- the app can't update those itself.
  /// Must be <= targetVersion. Set to the build that introduced DFlash
  /// drafting (`spec-type = draft-dflash`, llama.cpp PR #22105), the newest
  /// thing the app relies on -- older builds reject the spec type, so every
  /// model with a DFlash head would fail to load. The previous floor, b9726,
  /// was the `--agent` serve flag (llama.cpp PR #24801), which this build
  /// includes. Only raise this if the app starts relying on an even newer
  /// flag or value.
  static let floorVersion = LlamaVersion(parsing: "b9831")!

  /// The first build whose `serve --host` takes a comma-separated list of
  /// addresses (llama.cpp PR #28690), which is what lets a server bound to a
  /// specific address (e.g. Tailscale) keep answering on loopback too.
  ///
  /// It's above `floorVersion`, so it's a capability, not a requirement: the
  /// app checks the in-use engine against it and passes a list only when it's
  /// new enough, rather than raising the floor and nagging every Homebrew user
  /// below it. The check has to be exact -- an older engine reads the list as
  /// one hostname and binds nothing, so the server fails to start. Delete the
  /// check (and this) once `floorVersion` reaches it.
  static let multiHostVersion = LlamaVersion(parsing: "b11104")!

  /// Where the in-use binary comes from. Only `managed` is the app's to
  /// update; `brew` and `external` are both used as-is and never modified.
  /// Brew is split out so the footer can hint at the actual update channel
  /// (`brew upgrade`) instead of a generic "external" marker.
  enum Origin: Equatable { case managed, brew, external }

  /// Whether the binary at `path` is a Homebrew install. Follows symlinks and
  /// checks for Homebrew's Cellar layout (`bin/llama` is a symlink into
  /// `../Cellar/llama.cpp/...`) rather than the bin dir alone -- /usr/local/bin
  /// also hosts manual installs.
  private static func isHomebrew(at path: String) -> Bool {
    (path as NSString).resolvingSymlinksInPath.contains("/Cellar/")
  }

  /// Whether `pathEntry` is an `install.sh` copy the app should run: a real
  /// file rather than a symlink (`destinationOfSymbolicLink` doesn't follow
  /// links, so it succeeds exactly when the entry itself is one), at or above
  /// `targetVersion`. Runs the binary to read its version, so it blocks.
  private static func hasCurrentInstallScriptCopy() -> Bool {
    let fm = FileManager.default
    guard fm.isExecutableFile(atPath: pathEntry),
      (try? fm.destinationOfSymbolicLink(atPath: pathEntry)) == nil,
      let version = readVersion(at: pathEntry)
    else { return false }
    return version >= targetVersion
  }

  /// Dev affordance: pretend unmanaged installs (the `install.sh` copy,
  /// Homebrew) aren't present, so the missing -> install path can be exercised
  /// on a machine that already has llama.cpp. Toggle with:
  ///   defaults write app.llama.Llama.dev ignoreUnmanagedLlama -bool YES
  private static var ignoresUnmanaged: Bool {
    #if DEBUG
      return UserDefaults.standard.bool(forKey: "ignoreUnmanagedLlama")
    #else
      return false
    #endif
  }

  /// Resolves the active `llama` binary in the order described on the type.
  /// Nil when none is found, which is what sends the app down the install flow.
  ///
  /// Runs a `version` subprocess when an `install.sh` copy is present, so call
  /// off the main thread. Main-actor code (the server launch) reads the result
  /// cached on `LlamaInstallManager` instead.
  static func resolve() -> (path: String, origin: Origin)? {
    let fm = FileManager.default

    if !ignoresUnmanaged && hasCurrentInstallScriptCopy() {
      return (pathEntry, .external)
    }

    if fm.isExecutableFile(atPath: managedPath) {
      return (managedPath, .managed)
    }

    if ignoresUnmanaged {
      logger.debug("ignoreUnmanagedLlama set; ignoring unmanaged installs")
      return nil
    }

    for dir in unmanagedDirs {
      let path = dir + "/llama"
      if fm.isExecutableFile(atPath: path) {
        return (path, isHomebrew(at: path) ? .brew : .external)
      }
    }

    return nil
  }

  /// The path to the `llama` binary to invoke, or `nil` if none is installed.
  /// Blocks like `resolve()`, so call off the main thread.
  static var llamaPath: String? {
    guard let path = resolve()?.path else {
      logger.error("No llama binary found")
      return nil
    }
    logger.debug("Using llama binary at \(path, privacy: .public)")
    return path
  }

  /// Reads the version reported by the binary at `path`, or nil if it can't be
  /// run or its output can't be parsed. Runs `<path> version`, which just prints
  /// the build and exits -- no model load. Blocks on the subprocess, so call off
  /// the main thread.
  static func readVersion(at path: String) -> LlamaVersion? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: path)
    proc.arguments = ["version"]
    // Capture both streams into one pipe: which stream carries the version has
    // changed across builds (e.g. b10679 prints it to stderr, b11200 to
    // stdout), and the parser finds the build number either way.
    let out = Pipe()
    proc.standardOutput = out
    proc.standardError = out

    do {
      try proc.run()
    } catch {
      logger.error(
        "Couldn't run \(path, privacy: .public) version: \(error.localizedDescription, privacy: .public)"
      )
      return nil
    }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else { return nil }
    return LlamaVersion(parsing: String(decoding: data, as: UTF8.self))
  }
}
