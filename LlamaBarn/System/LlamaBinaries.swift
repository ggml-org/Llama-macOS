import Foundation
import os.log

/// Resolves the `llama` executable the app drives, and classifies who owns it.
///
/// The app follows a shared-path model:
/// - it owns the curl-install path (`~/.llama-app/llama`, what `install.sh`
///   produces): it may install a binary there and keep it updated
/// - any other install (e.g. Homebrew) is treated as external: the app uses it
///   but never modifies it
///
/// `llama` is the unified llama.cpp executable -- the server is `llama serve`
/// and memory profiling is `llama fit-params`, both subcommands of this one
/// binary. There is no separate `llama-server` / `llama-fit-params` to find.
enum LlamaBinaries {

  private static let logger = Logger(subsystem: Logging.subsystem, category: "LlamaBinaries")

  /// The curl-install path the app owns (matches `install.sh`'s layout).
  /// The real binary lives in `~/.llama-app`; `install.sh` also drops a
  /// `~/.local/bin/llama` symlink onto PATH, but the app points at the real file.
  static let appOwnedPath: String =
    (NSHomeDirectory() as NSString).appendingPathComponent(".llama-app/llama")

  /// External locations to probe when the app hasn't installed its own binary.
  /// Covers the Homebrew bin dirs (Apple Silicon and Intel).
  private static let externalDirs = ["/opt/homebrew/bin", "/usr/local/bin"]

  /// The build the app installs and keeps its own binary at -- the pinned
  /// target, not whatever is newest. Bump per app release after smoke-testing
  /// `serve` + `fit-params`; the app's auto-updater then rolls it out.
  static let targetVersion = LlamaVersion(parsing: "b9553")!

  /// The minimum build the app accepts from an external install (e.g. Homebrew)
  /// before nudging the user to update -- the app can't update those itself.
  /// Must be <= targetVersion; should track the oldest build whose `serve` /
  /// `fit-params` flags the app relies on (currently a conservative placeholder).
  static let floorVersion = LlamaVersion(parsing: "b9370")!

  /// Who owns the resolved binary -- determines who can update it.
  enum Ownership: Equatable { case appOwned, external }

  /// Where the `llama` binary is and who owns it.
  enum Resolution: Equatable {
    /// App-managed binary at the curl-install path; the app may update it.
    case appOwned(path: String)
    /// A pre-existing install (e.g. Homebrew); use it but never modify it.
    case external(path: String)
    /// No `llama` binary found anywhere; the install flow needs to run.
    case missing
  }

  /// Resolves the active `llama` binary. The app-owned path wins, then the
  /// external locations in order, else `.missing`.
  static func resolve() -> Resolution {
    let fm = FileManager.default

    if fm.isExecutableFile(atPath: appOwnedPath) {
      return .appOwned(path: appOwnedPath)
    }

    #if DEBUG
      // Dev affordance: pretend external installs (e.g. Homebrew) aren't present,
      // so the missing -> install path can be exercised on a machine that already
      // has llama.cpp. Toggle with:
      //   defaults write app.llamabarn.LlamaBarn.dev forceAppOwnedLlama -bool YES
      if UserDefaults.standard.bool(forKey: "forceAppOwnedLlama") {
        logger.debug("forceAppOwnedLlama set; ignoring external installs")
        return .missing
      }
    #endif

    for dir in externalDirs {
      let path = dir + "/llama"
      if fm.isExecutableFile(atPath: path) {
        return .external(path: path)
      }
    }

    return .missing
  }

  /// The path to the `llama` binary to invoke, or `nil` if none is installed.
  static var llamaPath: String? {
    switch resolve() {
    case .appOwned(let path), .external(let path):
      logger.debug("Using llama binary at \(path, privacy: .public)")
      return path
    case .missing:
      logger.error("No llama binary found")
      return nil
    }
  }

  /// What's installed: ownership plus the reported version (nil if it couldn't
  /// be read), or nothing at all. These are facts -- the target/floor policy
  /// that turns them into install/update/nudge decisions lives in
  /// `LlamaInstallManager`.
  enum Installed: Equatable {
    case present(ownership: Ownership, version: LlamaVersion?)
    case missing
  }

  /// Reads the version reported by the binary at `path`, or nil if it can't be
  /// run or its output can't be parsed. Runs `<path> version`, which just prints
  /// the build and exits -- no model load. Blocks on the subprocess, so call off
  /// the main thread.
  static func readVersion(at path: String) -> LlamaVersion? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: path)
    proc.arguments = ["version"]
    let out = Pipe()
    proc.standardOutput = out
    proc.standardError = Pipe()  // discard any chatter

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

  /// Resolves the binary and reads its version. Blocks on a `version`
  /// subprocess, so call off the main thread.
  static func installed() -> Installed {
    switch resolve() {
    case .missing:
      return .missing
    case .appOwned(let path):
      return .present(ownership: .appOwned, version: readVersion(at: path))
    case .external(let path):
      return .present(ownership: .external, version: readVersion(at: path))
    }
  }
}
