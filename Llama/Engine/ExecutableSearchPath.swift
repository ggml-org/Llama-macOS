import Foundation

enum ExecutableSearchPath {
  static let homebrewDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]

  static func serverPath(inherited: String?) -> String {
    // Finder does not inherit shell setup. Keep explicit PATH precedence and
    // append the same Homebrew locations used to discover the engine.
    let path = inherited ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    let existing = Set(path.split(separator: ":").map(String.init))
    let missing = homebrewDirectories.filter { !existing.contains($0) }
    return ([path] + missing).filter { !$0.isEmpty }.joined(separator: ":")
  }
}
