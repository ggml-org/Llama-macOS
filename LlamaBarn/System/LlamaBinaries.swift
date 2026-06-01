import Foundation
import os.log

/// Resolves where the llama.cpp executables (`llama-server`, `llama-fit-params`)
/// live on disk.
///
/// This is an exploratory branch for making the CLI a standalone install that
/// the app drives instead of carrying its own bundled copy. For this first step
/// the app takes NO responsibility for installing anything -- it assumes a
/// `llama.cpp` install is already present (via Homebrew) and just points at it.
///
/// There is deliberately no bundle fallback: if a model runs, it ran the external
/// binary, because there is no other. A missing install surfaces as a clear error
/// when the server/profiler validate the path before launching.
enum LlamaBinaries {

  private static let logger = Logger(subsystem: Logging.subsystem, category: "LlamaBinaries")

  /// Where Homebrew installs CLIs on Apple Silicon -- where we expect
  /// `llama-server` / `llama-fit-params` to already live.
  static let binDir: String = {
    let dir = "/opt/homebrew/bin"
    logger.info("Using llama.cpp binaries at \(dir, privacy: .public)")
    return dir
  }()

  /// Path to the `llama-server` executable.
  static var serverPath: String { binDir + "/llama-server" }

  /// Path to the `llama-fit-params` executable.
  static var fitParamsPath: String { binDir + "/llama-fit-params" }
}
