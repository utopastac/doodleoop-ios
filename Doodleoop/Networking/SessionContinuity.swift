import Foundation

/// Hooks `SessionContinuity` uses to change the live session without owning it.
@MainActor
protocol SessionContinuityContext: AnyObject {
  var role: GameSession.Role { get }
  var state: GameState? { get }
  var devicePlayerId: String { get }
  var discoveredPeers: [DiscoveredPeer] { get }
  var isReconnecting: Bool { get }
  var isMigratingHost: Bool { get }
  var hasTransport: Bool { get }
  var keepsInjectedTransport: Bool { get }

  func setRole(_ role: GameSession.Role)
  func setReconnecting(_ value: Bool)
  func setMigratingHost(_ value: Bool)
  func setStatusBanner(_ value: String?)
  func setHandoff(_ value: SeatHandoff?)

  func applyState(_ newState: GameState)
  func sync(_ newState: GameState, includeAvatars: Bool)
  func endJoinerSession(reason: SessionAlert)
  func attachHostTransport(resetPeers: Bool)
  func attachJoinerTransport()
  func cancelPhaseTimer()
  func schedulePhaseTimer()
  func prepareLocalHandoffIfNeeded()
  func scheduleDisconnectGrace(key: String, action: @escaping @MainActor () -> Void)
  func cancelDisconnectGrace(key: String)
  func refreshHostingAdvertisement()
  func ensureBrowsingAlongsideHosting()
  func ensureBrowsing()
  func connect(to peer: DiscoveredPeer)
  func tearDownTransport()
  func clearPeerBook()
}

/// Reconnect grace, host election, and yielding the network host.
@MainActor
final class SessionContinuity {
  /// Strong so the bridge stays alive. The bridge holds the session unowned.
  private var context: (any SessionContinuityContext)?
  /// Prior network host while seeking a migrated successor.
  private var previousHostDeviceId: String?

  func bind(_ context: any SessionContinuityContext) {
    self.context = context
  }

  func reset() {
    previousHostDeviceId = nil
    context?.setReconnecting(false)
    context?.setMigratingHost(false)
  }

  /// Clears reconnect flags after a fresh `syncState`. True when a banner should say reconnected.
  func noteLinkRestored() -> Bool {
    guard let context else { return false }
    let wasReconnecting = context.isReconnecting || context.isMigratingHost
    guard wasReconnecting else { return false }
    context.setReconnecting(false)
    context.setMigratingHost(false)
    previousHostDeviceId = nil
    context.cancelDisconnectGrace(key: "host")
    context.cancelDisconnectGrace(key: "migration")
    return true
  }

  func peersChanged() {
    guard let context else { return }
    if context.role == .host {
      considerYieldingToSuccessorHost()
    }
    if context.isReconnecting || context.isMigratingHost {
      connectDiscoveredPeers()
    }
  }

  func recoverAfterForeground() {
    guard let context else { return }
    if context.role == .host, context.state != nil {
      // Local peer links often die in background — keep advertising for rejoins.
      if context.hasTransport {
        context.refreshHostingAdvertisement()
      } else {
        context.attachHostTransport(resetPeers: false)
      }
      // Watch for a successor that took over while we were offline.
      context.ensureBrowsingAlongsideHosting()
      considerYieldingToSuccessorHost()
      context.schedulePhaseTimer()
    } else if context.role == .joiner, context.state != nil {
      beginJoinerReconnect()
    }
  }

  func beginJoinerReconnect() {
    guard let context else { return }
    let alreadyReconnecting = context.isReconnecting || context.isMigratingHost
    context.setReconnecting(true)
    context.setStatusBanner("Connection lost — trying to reconnect…")
    if context.hasTransport {
      context.ensureBrowsing()
    } else {
      context.attachJoinerTransport()
    }
    connectDiscoveredPeers()
    if !alreadyReconnecting {
      context.scheduleDisconnectGrace(key: "host") { [weak self] in
        self?.attemptHostMigrationAfterHostLoss()
      }
    }
  }

  /// After reconnect grace, elect a new network host among remaining phones.
  func attemptHostMigrationAfterHostLoss() {
    guard let context else { return }
    guard context.role == .joiner, var current = context.state else {
      context.setReconnecting(false)
      context.endJoinerSession(reason: .lostConnection)
      return
    }

    let previousHost = current.networkHostDeviceId.isEmpty
      ? (previousHostDeviceId ?? "")
      : current.networkHostDeviceId
    previousHostDeviceId = previousHost.isEmpty ? nil : previousHost

    if !previousHost.isEmpty, previousHost != context.devicePlayerId {
      current = GameEngine.handleDisconnect(deviceId: previousHost, from: current)
    }
    // Keep seats for devices still here — we're present.
    current = GameEngine.clearAbsent(deviceId: context.devicePlayerId, in: current)
    context.applyState(current)

    guard let winner = GameEngine.electedNetworkHostDeviceId(in: current) else {
      context.setReconnecting(false)
      context.setMigratingHost(false)
      context.endJoinerSession(reason: .lostConnection)
      return
    }

    if winner == context.devicePlayerId {
      promoteToNetworkHost(previousHostDeviceId: previousHost)
    } else {
      beginSeekingMigratedHost()
    }
  }

  func promoteToNetworkHost(previousHostDeviceId: String) {
    guard let context, var current = context.state else { return }
    context.setMigratingHost(true)
    context.setReconnecting(false)
    context.cancelDisconnectGrace(key: "host")
    context.cancelDisconnectGrace(key: "migration")

    if !previousHostDeviceId.isEmpty {
      current = GameEngine.handleDisconnect(deviceId: previousHostDeviceId, from: current)
    }
    current = GameEngine.clearAbsent(deviceId: context.devicePlayerId, in: current)
    current = GameEngine.claimNetworkHost(deviceId: context.devicePlayerId, in: current)

    context.setRole(.host)
    context.setHandoff(nil)
    context.applyState(current)
    // Unit tests inject RecordingMessageTransport — keep it instead of opening Bonjour.
    if context.keepsInjectedTransport {
      context.clearPeerBook()
    } else {
      context.tearDownTransport()
      context.attachHostTransport(resetPeers: true)
    }

    context.sync(current, includeAvatars: true)
    context.setMigratingHost(false)
    self.previousHostDeviceId = nil
    context.setStatusBanner("You're hosting now")
    context.prepareLocalHandoffIfNeeded()
  }

  func migrationTimedOut() {
    guard let context else { return }
    context.setReconnecting(false)
    context.setMigratingHost(false)
    context.endJoinerSession(reason: .lostConnection)
  }

  private func beginSeekingMigratedHost() {
    guard let context else { return }
    context.setMigratingHost(true)
    context.setReconnecting(true)
    context.setStatusBanner("Finding a new host…")
    if context.hasTransport {
      context.ensureBrowsing()
    } else {
      context.attachJoinerTransport()
    }
    connectDiscoveredPeers()
    context.scheduleDisconnectGrace(key: "migration") { [weak self] in
      self?.migrationTimedOut()
    }
  }

  private func considerYieldingToSuccessorHost() {
    guard let context, context.role == .host, let state = context.state else { return }
    let localDeviceId = context.devicePlayerId
    guard let successor = context.discoveredPeers.first(where: {
      shouldYield(to: $0, given: state, localDeviceId: localDeviceId)
    }) else { return }
    demoteAndJoin(successor)
  }

  private func shouldYield(
    to peer: DiscoveredPeer,
    given state: GameState,
    localDeviceId: String
  ) -> Bool {
    guard !state.roomId.isEmpty, peer.roomId == state.roomId else { return false }
    let peerEpoch = peer.epoch ?? 0
    if peerEpoch > state.stateEpoch { return true }
    if peerEpoch < state.stateEpoch { return false }
    guard let peerHost = peer.hostDeviceId, !peerHost.isEmpty else { return false }
    // Equal epoch tie-break — should be rare; lower device id wins.
    return peerHost < state.networkHostDeviceId && peerHost != localDeviceId
  }

  private func demoteAndJoin(_ peer: DiscoveredPeer) {
    guard let context else { return }
    context.setMigratingHost(true)
    context.setReconnecting(true)
    context.cancelPhaseTimer()
    context.setRole(.joiner)
    context.setStatusBanner("Another phone took over as host…")
    context.tearDownTransport()
    context.attachJoinerTransport()
    // Re-fetch peer from discovered list after browse starts; connect when listed.
    // Immediate connect if endpoint map already has it from prior parallel browse.
    context.connect(to: peer)
    context.scheduleDisconnectGrace(key: "migration") { [weak self] in
      self?.migrationTimedOut()
    }
  }

  private func connectDiscoveredPeers() {
    guard let context, context.role == .joiner else { return }
    for peer in relevantPeers() {
      context.connect(to: peer)
    }
  }

  private func relevantPeers() -> [DiscoveredPeer] {
    guard let context else { return [] }
    let peers = context.discoveredPeers
    guard let state = context.state else { return peers }
    let room = state.roomId
    if context.isMigratingHost {
      let previous = previousHostDeviceId ?? state.networkHostDeviceId
      return peers.filter { peer in
        guard peer.roomId == room || (room.isEmpty && peer.roomId == nil) else { return false }
        if let hostDevice = peer.hostDeviceId, !previous.isEmpty {
          return hostDevice != previous
        }
        return (peer.epoch ?? 0) > state.stateEpoch
      }
    }
    if room.isEmpty {
      return peers
    }
    let sameRoom = peers.filter { $0.roomId == room || $0.roomId == nil }
    return sameRoom.isEmpty ? peers : sameRoom
  }
}
