import Foundation
import XCTest

final class ExecutableSearchPathTests: XCTestCase {
  func testFinderPathIncludesBothHomebrewLocations() {
    XCTAssertEqual(
      ExecutableSearchPath.serverPath(inherited: "/usr/bin:/bin:/usr/sbin:/sbin"),
      "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin")
  }

  func testExplicitPrecedenceAndExistingHomebrewEntriesArePreserved() {
    let path = "/custom/bin:/usr/local/bin:/usr/bin:/opt/homebrew/bin"
    XCTAssertEqual(ExecutableSearchPath.serverPath(inherited: path), path)
  }

  func testMissingAndEmptyPathDoNotAddCurrentDirectorySearch() {
    XCTAssertEqual(
      ExecutableSearchPath.serverPath(inherited: nil),
      "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin")
    XCTAssertEqual(
      ExecutableSearchPath.serverPath(inherited: ""), "/opt/homebrew/bin:/usr/local/bin")
  }

  func testInheritedPathSyntaxIsNotRewritten() {
    let path = "/Custom Tools/bin::/usr/bin:/usr/local/bin"
    XCTAssertEqual(ExecutableSearchPath.serverPath(inherited: path), path + ":/opt/homebrew/bin")
  }

  func testChildProcessInheritsPreparedPath() throws {
    let path = ExecutableSearchPath.serverPath(inherited: "/usr/bin:/bin")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", "printf '%s' \"$PATH\""]
    process.environment = ["PATH": path]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    XCTAssertEqual(String(data: data, encoding: .utf8), path)
  }
}
