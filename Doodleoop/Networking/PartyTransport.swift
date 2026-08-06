import Foundation

/// A nearby host discovered over Bonjour.
struct DiscoveredPeer: Identifiable, Hashable, Sendable {
  /// Stable key for this browse result (service identity).
  let id: String
  let displayName: String
  /// Game room id from Bonjour TXT (`room`), when present.
  var roomId: String? = nil
  /// Host's `stateEpoch` from TXT (`epoch`).
  var epoch: Int? = nil
  /// Host device id from TXT (`hostDevice`).
  var hostDeviceId: String? = nil
}

/// Connection liveness for a peer key owned by the transport.
enum PeerLinkState: Equatable, Sendable {
  case connected
  case notConnected
}

/// Per-device connection status for in-game UI (host view of the room).
enum DeviceConnectionStatus: Equatable, Sendable {
  case connected
  case reconnecting
  case absent
}

struct DeviceConnectionPresence: Identifiable, Equatable, Sendable {
  var id: String { deviceId }
  let deviceId: String
  let name: String
  let status: DeviceConnectionStatus
  /// True for this phone's seats — hidden from the strip or shown as "You".
  let isLocal: Bool
}

/// Length-prefixed frames for reliable `NetworkMessage` blobs over a TCP stream.
enum MessageFraming {
  static let headerSize = 4
  /// Reject absurd frames (full pad syncs with ink stay well under this).
  static let maxPayloadSize = 8 * 1024 * 1024

  static func encode(_ payload: Data) -> Data {
    var length = UInt32(payload.count).bigEndian
    var framed = Data(bytes: &length, count: headerSize)
    framed.append(payload)
    return framed
  }

  struct Decoder: Sendable {
    private var buffer = Data()

    mutating func append(_ chunk: Data) throws -> [Data] {
      buffer.append(chunk)
      var messages: [Data] = []
      while buffer.count >= MessageFraming.headerSize {
        let length = buffer.prefix(MessageFraming.headerSize).withUnsafeBytes { raw in
          raw.load(as: UInt32.self).bigEndian
        }
        let payloadLength = Int(length)
        guard payloadLength >= 0, payloadLength <= MessageFraming.maxPayloadSize else {
          buffer.removeAll()
          throw FramingError.invalidLength(payloadLength)
        }
        let total = MessageFraming.headerSize + payloadLength
        guard buffer.count >= total else { break }
        let payload = buffer.subdata(in: MessageFraming.headerSize..<total)
        buffer.removeSubrange(0..<total)
        messages.append(payload)
      }
      return messages
    }
  }

  enum FramingError: Error {
    case invalidLength(Int)
  }
}

@MainActor
protocol PartyTransportDelegate: AnyObject {
  func transport(_ transport: any PartyTransport, didReceive data: Data, fromPeerKey peerKey: String)
  func transport(_ transport: any PartyTransport, peer peerKey: String, didChange state: PeerLinkState)
  func transport(_ transport: any PartyTransport, discoveredPeersDidChange peers: [DiscoveredPeer])
  func transportDidFailToAdvertise(_ transport: any PartyTransport, error: Error)
  func transportDidFailToBrowse(_ transport: any PartyTransport, error: Error)
}

/// Local-network party transport: host listens, joiners connect out.
@MainActor
protocol PartyTransport: AnyObject {
  var delegate: PartyTransportDelegate? { get set }

  func startHosting(discoveryInfo: [String: String])
  /// Restart Bonjour advertising without dropping live connections.
  func refreshHosting(discoveryInfo: [String: String])
  func startBrowsing()
  func ensureBrowsing()
  /// Browse while still hosting (used to detect a migrated successor host).
  func ensureBrowsingAlongsideHosting()
  func connect(to peer: DiscoveredPeer)
  func send(_ data: Data, to peerKey: String?)
  func disconnectPeer(_ peerKey: String)
  func stop()
}
