import Foundation

/// Detects a Tailscale address on this Mac.
///
/// Binding the server to the Tailscale interface is the best answer we can
/// give someone who wants to reach their models from another device: it works
/// from anywhere rather than only at home, Tailscale authenticates the device
/// and encrypts the traffic, and -- unlike binding `0.0.0.0` -- the server
/// stays invisible on whatever wifi the laptop happens to be on. It needs no
/// credentials of our own, which is why the app can offer it without shipping
/// an auth layer around a server that has none.
///
/// We only surface it when it's already installed and logged in. The app
/// doesn't advertise, prompt for, or install Tailscale.
enum TailscaleInterface {
  /// Whether an address looks like Tailscale's, by range alone.
  ///
  /// Used to classify an address we already stored, where the question is what
  /// the user chose rather than what exists right now -- a Tailscale bind
  /// stays a Tailscale bind while Tailscale is signed out. Detection of a
  /// *live* address is stricter (see `address()`).
  ///
  /// Tailscale hands out addresses from the CGNAT range, 100.64.0.0/10.
  static func isTailscaleAddress(_ ip: String) -> Bool {
    let parts = ip.split(separator: ".").compactMap { Int($0) }
    guard parts.count == 4, parts[0] == 100 else { return false }
    return (64...127).contains(parts[1])
  }

  /// This Mac's Tailscale address, or nil when Tailscale isn't running or is
  /// logged out (either way, no such interface exists).
  ///
  /// Requires *both* the CGNAT range and a `utun` interface: some ISPs hand
  /// out 100.64/10 addresses on real interfaces, and binding the server to a
  /// carrier's CGNAT address instead of a private overlay would be precisely
  /// the wrong outcome.
  static func address() -> String? {
    LocalNetwork.ipv4Addresses()
      .filter { $0.key.hasPrefix("utun") && isTailscaleAddress($0.value) }
      .values
      .sorted()  // stable when more than one utun qualifies
      .first
  }

  /// Whether `address` is the one this Mac holds right now. False for a
  /// stored address that has gone stale -- signed out, or a different tailnet.
  static func isCurrentAddress(_ address: String) -> Bool {
    self.address() == address
  }
}
