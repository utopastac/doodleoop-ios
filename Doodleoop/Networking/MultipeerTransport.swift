import Foundation
@preconcurrency import MultipeerConnectivity
import Combine

protocol MultipeerTransportDelegate: AnyObject {
  func transport(_ transport: MultipeerTransport, didReceive data: Data, from peerID: MCPeerID)
  func transport(_ transport: MultipeerTransport, peer peerID: MCPeerID, didChange state: MCSessionState)
  func transport(_ transport: MultipeerTransport, foundPeer peerID: MCPeerID, discoveryInfo: [String: String]?)
  func transport(_ transport: MultipeerTransport, lostPeer peerID: MCPeerID)
  func transport(_ transport: MultipeerTransport, didFailToAdvertise error: Error)
  func transport(_ transport: MultipeerTransport, didFailToBrowse error: Error)
}

/// Thin Multipeer Connectivity wrapper. Apps supply a Bonjour `serviceType` and encode their own messages.
final class MultipeerTransport: NSObject, ObservableObject, @unchecked Sendable {
  let serviceType: String
  let myPeerID: MCPeerID

  private let session: MCSession
  private var advertiser: MCNearbyServiceAdvertiser?
  private var browser: MCNearbyServiceBrowser?

  weak var delegate: MultipeerTransportDelegate?
  /// Host sets this so mid-round invites can be rejected.
  var shouldAcceptInvitation: (@Sendable () -> Bool)?

  @Published private(set) var connectedPeers: [MCPeerID] = []
  @Published private(set) var discoveredPeers: [MCPeerID] = []

  init(displayName: String, serviceType: String) {
    self.serviceType = serviceType
    myPeerID = MCPeerID(displayName: String(displayName.prefix(20)))
    session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
    super.init()
    session.delegate = self
  }

  func startHosting(discoveryInfo: [String: String]? = nil) {
    stopBrowsing()
    advertiser = MCNearbyServiceAdvertiser(
      peer: myPeerID,
      discoveryInfo: discoveryInfo,
      serviceType: serviceType
    )
    advertiser?.delegate = self
    advertiser?.startAdvertisingPeer()
  }

  func startBrowsing() {
    stopHosting()
    discoveredPeers = []
    browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
    browser?.delegate = self
    browser?.startBrowsingForPeers()
  }

  func stopHosting() {
    advertiser?.stopAdvertisingPeer()
    advertiser = nil
  }

  func stopBrowsing() {
    browser?.stopBrowsingForPeers()
    browser = nil
    discoveredPeers = []
  }

  func invite(_ peer: MCPeerID) {
    browser?.invitePeer(peer, to: session, withContext: nil, timeout: 20)
  }

  func disconnect() {
    stopHosting()
    stopBrowsing()
    session.disconnect()
    connectedPeers = []
  }

  func send(_ data: Data, to peers: [MCPeerID]? = nil) {
    let targets = peers ?? session.connectedPeers
    guard !targets.isEmpty else { return }
    do {
      try session.send(data, toPeers: targets, with: .reliable)
    } catch {
      print("MultipeerTransport: failed to send: \(error)")
    }
  }

  func send<Message: Encodable>(_ message: Message, to peers: [MCPeerID]? = nil) {
    do {
      let data = try JSONEncoder().encode(message)
      send(data, to: peers)
    } catch {
      print("MultipeerTransport: failed to encode: \(error)")
    }
  }
}

extension MultipeerTransport: MCSessionDelegate {
  func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
    let peers = session.connectedPeers
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.connectedPeers = peers
      self.delegate?.transport(self, peer: peerID, didChange: state)
    }
  }

  func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.delegate?.transport(self, didReceive: data, from: peerID)
    }
  }

  func session(
    _ session: MCSession,
    didReceive stream: InputStream,
    withName streamName: String,
    fromPeer peerID: MCPeerID
  ) {}

  func session(
    _ session: MCSession,
    didStartReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    with progress: Progress
  ) {}

  func session(
    _ session: MCSession,
    didFinishReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    at localURL: URL?,
    withError error: Error?
  ) {}
}

extension MultipeerTransport: MCNearbyServiceAdvertiserDelegate {
  func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser,
    didReceiveInvitationFromPeer peerID: MCPeerID,
    withContext context: Data?,
    invitationHandler: @escaping (Bool, MCSession?) -> Void
  ) {
    let accept = shouldAcceptInvitation?() ?? true
    invitationHandler(accept, accept ? session : nil)
  }

  func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser,
    didNotStartAdvertisingPeer error: Error
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.delegate?.transport(self, didFailToAdvertise: error)
    }
  }
}

extension MultipeerTransport: MCNearbyServiceBrowserDelegate {
  func browser(
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

  func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.discoveredPeers.removeAll { $0 == peerID }
      self.delegate?.transport(self, lostPeer: peerID)
    }
  }

  func browser(
    _ browser: MCNearbyServiceBrowser,
    didNotStartBrowsingForPeers error: Error
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.delegate?.transport(self, didFailToBrowse: error)
    }
  }
}
