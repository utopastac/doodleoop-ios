import Foundation
import MultipeerConnectivity

/// Outbound messaging seam so GameSession can be tested without Multipeer.
@MainActor
protocol GameMessageTransport: AnyObject {
  func send(_ message: NetworkMessage)
  func disconnect()
}

/// Adapts MultipeerTransport to GameMessageTransport.
@MainActor
final class MultipeerMessageTransport: GameMessageTransport {
  private let transport: MultipeerTransport

  init(_ transport: MultipeerTransport) {
    self.transport = transport
  }

  func send(_ message: NetworkMessage) {
    transport.send(message)
  }

  func disconnect() {
    transport.disconnect()
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
