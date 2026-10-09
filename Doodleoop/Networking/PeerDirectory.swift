import Foundation

/// Transport peer key → durable `deviceId`.
struct PeerDirectory: Equatable {
  private(set) var deviceIds: [String: String]

  init(deviceIds: [String: String] = [:]) {
    self.deviceIds = deviceIds
  }

  mutating func bind(_ peerKey: String, to deviceId: String) {
    // Drop stale keys for the same device (reconnect gets a new connection id).
    deviceIds = deviceIds.filter { $0.value != deviceId || $0.key == peerKey }
    deviceIds[peerKey] = deviceId
  }

  mutating func unbind(_ peerKey: String) {
    deviceIds[peerKey] = nil
  }

  mutating func removeAll() {
    deviceIds.removeAll()
  }

  /// Bound device, or the peer key itself when the connection never said hello.
  func deviceId(for peerKey: String) -> String {
    deviceIds[peerKey] ?? peerKey
  }

  func boundDeviceId(for peerKey: String) -> String? {
    deviceIds[peerKey]
  }

  func keys(for deviceId: String) -> [String] {
    deviceIds.compactMap { $0.value == deviceId ? $0.key : nil }
  }

  func hasLiveClaim(deviceId: String, except peerKey: String) -> Bool {
    deviceIds.contains { $0.value == deviceId && $0.key != peerKey }
  }
}
