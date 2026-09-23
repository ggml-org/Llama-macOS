import Foundation
import OSLog

/// Identifies *which* network the Mac is currently attached to.
///
/// Exists for one job: local-network access (`UserSettings.networkAccess`) is a
/// single global switch, but consent to it isn't global. Someone turns it on
/// at home to reach the server from their phone, shuts the lid, and opens it
/// on café wifi -- where the same switch now offers an unauthenticated server
/// to strangers. The user agreed to expose it on *that* network, not on every
/// network the laptop later joins.
///
/// The fingerprint is the default gateway's IP plus its MAC address. The IP
/// alone is useless as an identity (half the routers on earth are
/// `192.168.1.1`); the MAC is what actually distinguishes your router from the
/// café's. Neither requires Location permission, unlike reading the wifi SSID.
enum NetworkIdentity {
  private static let logger = Logger(subsystem: Logging.subsystem, category: "NetworkIdentity")

  /// A stable-enough handle on the current network, or nil when there's no
  /// default route (no network, or a link with no gateway).
  ///
  /// Nil is deliberately *not* treated as "a different network" by callers --
  /// a laptop with wifi off hasn't moved anywhere, and flipping the setting
  /// off on every transient dropout would be its own kind of broken.
  static func currentFingerprint() -> String? {
    guard let router = LocalNetwork.routerAddress() else { return nil }
    guard let mac = hardwareAddress(for: router) else {
      // The gateway may not be in the ARP cache yet right after a link change.
      // Returning nil (rather than the bare IP) keeps a half-known network from
      // masquerading as a distinct one.
      logger.debug("router \(router, privacy: .private) not in ARP cache yet")
      return nil
    }
    return "\(router)|\(mac)"
  }

  /// MAC address of an IPv4 neighbour, read out of the kernel's ARP table.
  ///
  /// This is what `arp -n <ip>` prints, obtained the same way it does: a
  /// `sysctl` walk of the routing table filtered to link-level entries. Each
  /// message is a `rt_msghdr` followed by a `sockaddr_inarp` (the IP) and a
  /// `sockaddr_dl` (the hardware address), so we step through by `rtm_msglen`.
  private static func hardwareAddress(for ip: String) -> String? {
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, Int32(RTF_LLINFO)]
    var size = 0
    guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }

    var buf = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, u_int(mib.count), &buf, &size, nil, 0) == 0 else { return nil }

    var offset = 0
    while offset < size {
      let match: String? = buf.withUnsafeBytes { raw -> String? in
        let base = raw.baseAddress!.advanced(by: offset)
        let sinPtr = base.advanced(by: MemoryLayout<rt_msghdr>.stride)
        let sin = sinPtr.assumingMemoryBound(to: sockaddr_inarp.self).pointee

        var addr = sin.sin_addr
        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &addr, &text, socklen_t(INET_ADDRSTRLEN))
        guard String(cString: text) == ip else { return nil }

        // The link-level address follows the IP, and its bytes sit past the
        // interface name inside `sdl_data`.
        let sdlPtr = sinPtr.advanced(by: Int(sin.sin_len))
        let sdl = sdlPtr.assumingMemoryBound(to: sockaddr_dl.self).pointee
        guard sdl.sdl_alen == 6 else { return nil }

        let macBase = sdlPtr
          .advanced(by: MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data)!)
          .assumingMemoryBound(to: UInt8.self)
          .advanced(by: Int(sdl.sdl_nlen))
        return (0..<6).map { String(format: "%02x", macBase[$0]) }.joined(separator: ":")
      }
      if let match { return match }

      let msglen = buf.withUnsafeBytes {
        $0.baseAddress!.advanced(by: offset)
          .assumingMemoryBound(to: rt_msghdr.self).pointee.rtm_msglen
      }
      guard msglen > 0 else { break }
      offset += Int(msglen)
    }
    return nil
  }
}
