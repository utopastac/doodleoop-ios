import Foundation

/// Outbound messaging seam so GameSession can be tested without a live transport.
@MainActor
protocol GameMessageTransport: AnyObject {
  func send(_ message: NetworkMessage)
  func disconnect()
}

/// Encodes `NetworkMessage` and fans out through `PartyTransport`.
@MainActor
final class PartyMessageTransport: GameMessageTransport {
  private let transport: PartyTransport

  init(_ transport: PartyTransport) {
    self.transport = transport
  }

  func send(_ message: NetworkMessage) {
    do {
      let data = try JSONEncoder().encode(message)
      transport.send(data, to: nil)
    } catch {
      print("PartyMessageTransport: failed to encode: \(error)")
    }
  }

  func disconnect() {
    transport.stop()
  }
}

/// In-memory transport for unit tests — records outbound messages.
@MainActor
final class RecordingMessageTransport: GameMessageTransport {
  private(set) var sent: [NetworkMessage] = []
  private(set) var didDisconnect = false

  func send(_ message: NetworkMessage) {
    sent.append(message)
  }

  func disconnect() {
    didDisconnect = true
  }

  func reset() {
    sent = []
    didDisconnect = false
  }
}
