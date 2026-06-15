import Foundation

/// Utility for system memory detection and formatting
enum SystemMemory {

  // Cache physical memory for the session; RAM doesn't change at runtime.
  // Still honors BARN_SIMULATE_MEM_GB if set at launch.
  private static let physicalMemBytes: UInt64 = {
    if let simulatedGB = ProcessInfo.processInfo.environment["BARN_SIMULATE_MEM_GB"],
      let gb = Double(simulatedGB), gb > 0
    {
      return UInt64(gb * 1024 * 1024 * 1024)
    }
    var size = MemoryLayout<UInt64>.size
    var memsize: UInt64 = 0
    let result = sysctlbyname("hw.memsize", &memsize, &size, nil, 0)
    return result == 0 ? memsize : 0
  }()

  /// Returns cached system memory in bytes for this process lifetime.
  static var memoryBytes: UInt64 { physicalMemBytes }

  /// Gets system memory in Mb
  static var memoryMb: UInt64 {
    return memoryBytes / (1024 * 1024)
  }
}
