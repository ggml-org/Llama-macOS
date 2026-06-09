import Darwin
import Foundation
import os.log

/// Installs and updates the app-managed `llama` CLI by fetching prebuilt binaries
/// from the same Hugging Face bucket the official `install.sh` uses, laid out the same way:
/// the real binary at `~/.llama-app/llama` plus a `~/.local/bin/llama` symlink
/// so `llama` works from a terminal too.
///
/// macOS ships no zstd and the bucket serves the binary zstd-compressed, so we
/// fetch the bucket's small standalone `unzstd` helper (cached alongside the
/// binary) and pipe the download through it.
///
/// This only ever writes the managed path. A Homebrew (or other unmanaged)
/// install is never touched -- see `LlamaBinaries`.
enum LlamaInstaller {

  private static let logger = Logger(subsystem: Logging.subsystem, category: "LlamaInstaller")

  /// Root of the prebuilt-binary bucket. `…/resolve/latest` returns the current
  /// version tag (e.g. `b9444`); `…/resolve/<ver>/<arch>/<os>/…` are artifacts.
  private static let bucketBase =
    "https://huggingface.co/buckets/ggml-org/install.sh/resolve"

  /// We only ship prebuilt Apple Silicon (Metal) macOS binaries.
  private static let arch = "aarch64"
  private static let os = "macos"

  /// The real binary path (also what `LlamaBinaries` resolves as `.managed`).
  private static var llamaPath: String { LlamaBinaries.managedPath }

  /// Install dir the app manages. Holds the binary and the cached `unzstd` helper.
  private static var installDir: String {
    (LlamaBinaries.managedPath as NSString).deletingLastPathComponent
  }
  private static var unzstdPath: String { installDir + "/unzstd" }

  /// The on-PATH symlink `install.sh` creates so `llama` works in a terminal.
  private static var symlinkDir: String {
    (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin")
  }
  private static var symlinkPath: String { symlinkDir + "/llama" }

  enum InstallError: Error, LocalizedError {
    case unsupportedHardware(String)
    case downloadFailed(String)
    case decompressFailed(String)
    case installFailed(String)

    var errorDescription: String? {
      switch self {
      case .unsupportedHardware(let detail):
        return "No prebuilt llama binary for this Mac (\(detail))."
      case .downloadFailed(let detail):
        return "Download failed: \(detail)"
      case .decompressFailed(let detail):
        return "Couldn't unpack the llama binary: \(detail)"
      case .installFailed(let detail):
        return "Couldn't install the llama binary: \(detail)"
      }
    }
  }

  // MARK: - Public API

  /// Installs (or replaces) the app-managed `llama` binary at `version`.
  static func install(version: String) async throws {
    logger.info("Installing llama \(version, privacy: .public)")

    let config = try metalConfig()
    try await ensureUnzstd(version: version)

    let zstURL = try await download(
      "\(bucketBase)/\(version)/\(arch)/\(os)/metal/\(config)/llama-app.zst")
    defer { try? FileManager.default.removeItem(at: zstURL) }

    try decompressToLlama(zst: zstURL)
    linkOnPath()

    logger.info("Installed llama \(version, privacy: .public) at \(llamaPath, privacy: .public)")
  }

  // MARK: - Steps

  /// Maps this Mac's CPU to a Metal bucket config (`m1`…`m5`), mirroring
  /// `install.sh`, which buckets every M-series variant (Pro/Max/Ultra) by
  /// generation number.
  private static func metalConfig() throws -> String {
    var size = 0
    sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
    guard size > 0 else { throw InstallError.unsupportedHardware("unknown CPU") }
    var buf = [CChar](repeating: 0, count: size)
    sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
    let brand = String(cString: buf)

    guard let range = brand.range(of: "Apple M[1-5]", options: .regularExpression),
      let digit = brand[range].last
    else {
      throw InstallError.unsupportedHardware(brand)
    }
    return "m\(digit)"
  }

  /// Ensures the `unzstd` helper is present, fetching it once and caching it
  /// next to the binary. Subsequent installs/updates reuse it.
  private static func ensureUnzstd(version: String) async throws {
    if FileManager.default.isExecutableFile(atPath: unzstdPath) { return }
    let tmp = try await download("\(bucketBase)/\(version)/\(arch)/\(os)/unzstd")
    defer { try? FileManager.default.removeItem(at: tmp) }
    try atomicInstall(from: tmp, to: unzstdPath)
  }

  /// Decompresses `zst` through the `unzstd` helper and atomically swaps the
  /// result into `llamaPath`. The temp output lives in `installDir` so the final
  /// `rename(2)` is a same-volume atomic replace -- a crash never leaves a
  /// half-written binary in place.
  private static func decompressToLlama(zst: URL) throws {
    let fm = FileManager.default
    try fm.createDirectory(atPath: installDir, withIntermediateDirectories: true)

    let tmpOut = installDir + "/llama.tmp-\(UUID().uuidString)"
    guard fm.createFile(atPath: tmpOut, contents: nil) else {
      throw InstallError.decompressFailed("couldn't create \(tmpOut)")
    }

    do {
      guard let outHandle = FileHandle(forWritingAtPath: tmpOut) else {
        throw InstallError.decompressFailed("couldn't open \(tmpOut)")
      }
      let inHandle = try FileHandle(forReadingFrom: zst)
      let errPipe = Pipe()

      // unzstd with no args decompresses stdin -> stdout.
      let proc = Process()
      proc.executableURL = URL(fileURLWithPath: unzstdPath)
      proc.standardInput = inHandle
      proc.standardOutput = outHandle
      proc.standardError = errPipe

      try proc.run()
      proc.waitUntilExit()
      try? inHandle.close()
      try? outHandle.close()

      guard proc.terminationStatus == 0 else {
        let err = String(
          decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        throw InstallError.decompressFailed(
          "unzstd exited \(proc.terminationStatus): \(err.prefix(200))")
      }

      try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmpOut)
      guard rename(tmpOut, llamaPath) == 0 else {
        throw InstallError.installFailed("rename: \(String(cString: strerror(errno)))")
      }
    } catch {
      try? fm.removeItem(atPath: tmpOut)
      throw error
    }
  }

  /// Mirrors `install.sh`'s `ln -sf`: point `~/.local/bin/llama` at our
  /// binary so it's available in a terminal. Best-effort -- the app resolves the
  /// real path directly, so a failure here doesn't break the app. We won't
  /// clobber a real file a user may have placed there; only absent or symlink
  /// entries are (re)written.
  private static func linkOnPath() {
    let fm = FileManager.default
    do {
      try fm.createDirectory(atPath: symlinkDir, withIntermediateDirectories: true)

      if (try? fm.destinationOfSymbolicLink(atPath: symlinkPath)) != nil {
        try fm.removeItem(atPath: symlinkPath)  // replace our (or any) existing symlink
      } else if fm.fileExists(atPath: symlinkPath) {
        logger.info("Leaving existing non-symlink at \(symlinkPath, privacy: .public)")
        return
      }
      try fm.createSymbolicLink(atPath: symlinkPath, withDestinationPath: llamaPath)
    } catch {
      logger.error("Couldn't create PATH symlink: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Helpers

  /// Downloads a URL to a temp file, following HF's redirect to the CDN.
  private static func download(_ urlString: String) async throws -> URL {
    guard let url = URL(string: urlString) else {
      throw InstallError.downloadFailed("bad URL: \(urlString)")
    }
    let (tempURL, response) = try await URLSession.shared.download(from: url)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      let code = (response as? HTTPURLResponse)?.statusCode ?? -1
      throw InstallError.downloadFailed("\(urlString) (HTTP \(code))")
    }
    return tempURL
  }

  /// Copies `src` (possibly on another volume) onto the destination volume, then
  /// atomically renames it into place as an executable.
  private static func atomicInstall(from src: URL, to dest: String) throws {
    let fm = FileManager.default
    try fm.createDirectory(
      atPath: (dest as NSString).deletingLastPathComponent, withIntermediateDirectories: true)

    let tmp = dest + ".tmp-\(UUID().uuidString)"
    do {
      try fm.copyItem(at: src, to: URL(fileURLWithPath: tmp))
      try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp)
      guard rename(tmp, dest) == 0 else {
        throw InstallError.installFailed("rename \(dest): \(String(cString: strerror(errno)))")
      }
    } catch {
      try? fm.removeItem(atPath: tmp)
      throw error
    }
  }
}
