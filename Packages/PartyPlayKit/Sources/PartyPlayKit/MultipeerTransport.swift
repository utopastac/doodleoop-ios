import Foundation
@preconcurrency import MultipeerConnectivity
import Combine

public protocol MultipeerTransportDelegate: AnyObject {
  func transport(_ transport: MultipeerTransport, didReceive data: Data, from peerID: MCPeerID)
  func transport(_ transport: MultipeerTransport, peer peerID: MCPeerID, didChange state: MCSessionState)
  func transport(_ transport: MultipeerTransport, foundPeer peerID: MCPeerID, discoveryInfo: [String: String]?)
  func transport(_ transport: MultipeerTransport, lostPeer peerID: MCPeerID)
}

/// Thin Multipeer Connectivity wrapper. Apps supply a Bonjour `serviceType` and encode their own messages.
public final class MultipeerTransport: NSObject, ObservableObject, @unchecked Sendable {
  public let serviceType: String
  public let myPeerID: MCPeerID

  private let session: MCSession
  private var advertiser: MCNearbyServiceAdvertiser?
  private var browser: MCNearbyServiceBrowser?

  public weak var delegate: MultipeerTransportDelegate?

  @Published public private(set) var connectedPeers: [MCPeerID] = []
  @Published public private(set) var discoveredPeers: [MCPeerID] = []

  public init(displayName: String, serviceType: String) {
    self.serviceType = serviceType
    myPeerID = MCPeerID(displayName: String(displayName.prefix(20)))
    session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
    super.init()
    session.delegate = self
  }

  public func startHosting(discoveryInfo: [String: String]? = nil) {
    stopBrowsing()
    advertiser = MCNearbyServiceAdvertiser(
      peer: myPeerID,
      discoveryInfo: discoveryInfo,
      serviceType: serviceType
    )
    advertiser?.delegate = self
    advertiser?.startAdvertisingPeer()
  }

  public func startBrowsing() {
    stopHosting()
    discoveredPeers = []
    browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
    browser?.delegate = self
    browser?.startBrowsingForPeers()
  }

  public func stopHosting() {
    advertiser?.stopAdvertisingPeer()
    advertiser = nil
  }

  public func stopBrowsing() {
    browser?.stopBrowsingForPeers()
    browser = nil
    discoveredPeers = []
  }

  public func invite(_ peer: MCPeerID) {
    browser?.invitePeer(peer, to: session, withContext: nil, timeout: 20)
  }

  public func disconnect() {
    stopHosting()
    stopBrowsing()
    session.disconnect()
    connectedPeers = []
  }

  public func send(_ data: Data, to peers: [MCPeerID]? = nil) {
    let targets = peers ?? session.connectedPeers
    guard !targets.isEmpty else { return }
    do {
      try session.send(data, toPeers: targets, with: .reliable)
    } catch {
      print("PartyPlayKit: failed to send: \(error)")
    }
  }

  public func send<Message: Encodable>(_ message: Message, to peers: [MCPeerID]? = nil) {
    do {
      let data = try JSONEncoder().encode(message)
      send(data, to: peers)
    } catch {
      print("PartyPlayKit: failed to encode: \(error)")
    }
  }
}

extension MultipeerTransport: MCSessionDelegate {
  public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
    let peers = session.connectedPeers
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.connectedPeers = peers
      self.delegate?.transport(self, peer: peerID, didChange: state)
    }
  }

  public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.delegate?.transport(self, didReceive: data, from: peerID)
    }
  }

  public func session(
    _ session: MCSession,
    didReceive stream: InputStream,
    withName streamName: String,
    fromPeer peerID: MCPeerID
  ) {}

  public func session(
    _ session: MCSession,
    didStartReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    with progress: Progress
  ) {}

  public func session(
    _ session: MCSession,
    didFinishReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    at localURL: URL?,
    withError error: Error?
  ) {}
}

extension MultipeerTransport: MCNearbyServiceAdvertiserDelegate {
  public func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser,
    didReceiveInvitationFromPeer peerID: MCPeerID,
    withContext context: Data?,
    invitationHandler: @escaping (Bool, MCSession?) -> Void
  ) {
    invitationHandler(true, session)
  }
}

extension MultipeerTransport: MCNearbyServiceBrowserDelegate {
  public func browser(
    _ browser: MCNearbyServiceBrowser,
    foundPeer peerID: MCPeerID,
    withDiscoveryInfo info: [String: String]?
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if !self.discoveredPeers.contains(peerID) {
        self.discoveredPeers.append(peerID)
      }
      self.delegate?.transport(self, foundPeer: peerID, discoveryInfo: info)
    }
  }

  public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.discoveredPeers.removeAll { $0 == peerID }
      self.delegate?.transport(self, lostPeer: peerID)
    }
  }
}
