import Foundation
import SystemConfiguration

/// Read-only facts about this Mac's network: its addresses, and the default
/// route (primary interface and gateway). Shared by the server's bind-address
/// logic, `TailscaleInterface` and `NetworkIdentity`.
enum LocalNetwork {
  /// The default gateway's IPv4 address, or nil with no default route.
  static func routerAddress() -> String? {
    globalIPv4State()?["Router"] as? String
  }

  /// The dynamic store's global IPv4 state -- where macOS records the default
  /// route's interface and gateway.
  private static func globalIPv4State() -> [String: Any]? {
    guard let store = SCDynamicStoreCreate(nil, "app.llama.Llama" as CFString, nil, nil)
    else { return nil }
    return SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
      as? [String: Any]
  }

  /// The interface carrying the default route, e.g. `en0` on a Wi-Fi Mac or
  /// `en1` on one plugged into Ethernet. Read from the dynamic store rather
  /// than assumed, because which interface that is varies per machine -- the
  /// old hardcoded `en0` was wrong on any Mac whose primary link isn't Wi-Fi.
  private static func primaryInterfaceName() -> String? {
    globalIPv4State()?["PrimaryInterface"] as? String
  }

  /// The Mac's own IPv4 address on the network, for showing a URL other
  /// devices can reach.
  ///
  /// Prefers the interface holding the default route. Falls back to any
  /// non-loopback IPv4 so a machine with no default route (an isolated LAN,
  /// or Wi-Fi off with only a VPN up) still shows something reachable rather
  /// than the unusable `0.0.0.0`.
  static func ipAddress() -> String? {
    let addresses = ipv4Addresses()
    if let primary = primaryInterfaceName(), let match = addresses[primary] {
      return match
    }
    // No default route, or its interface has no IPv4 -- take whatever else is
    // up. Sorted for a stable pick: two runs shouldn't show different URLs.
    return addresses.values.sorted().first
  }

  /// Non-loopback IPv4 addresses, keyed by interface name. `TailscaleInterface`
  /// picks its overlay address out of this.
  static func ipv4Addresses() -> [String: String] {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?

    // Get linked list of all network interfaces (returns 0 on success)
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [:] }
    // Ensure memory is freed when function exits
    defer { freeifaddrs(ifaddr) }

    var result: [String: String] = [:]

    for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
      let interface = ifptr.pointee

      // Skip non-IPv4 addresses (AF_INET = IPv4, AF_INET6 = IPv6)
      guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

      // Skip interfaces that are down, and loopback (127.x is not reachable
      // from another machine, so it's never the answer here).
      let flags = Int32(interface.ifa_flags)
      guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }

      let name = String(cString: interface.ifa_name)

      // Convert socket address to human-readable IP string
      var addr = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      getnameinfo(
        interface.ifa_addr,
        socklen_t(interface.ifa_addr.pointee.sa_len),
        &addr,
        socklen_t(addr.count),
        nil,
        socklen_t(0),
        NI_NUMERICHOST  // Return numeric address (e.g., "192.168.1.5")
      )

      // First address wins per interface -- an interface can carry several
      // aliases, and the first is the one macOS treats as primary for it.
      let ip = String(cString: addr)
      if result[name] == nil, !ip.isEmpty {
        result[name] = ip
      }
    }

    return result
  }
}
