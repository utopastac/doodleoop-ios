import Foundation

/// What the host should do with one inbound message.
/// `GameSession` applies the steps in order so reconnect bookkeeping stays in one place.
@MainActor
enum HostInbox {
  enum Step {
    case bind(peerKey: String, deviceId: String)
    case unbind(String)
    case cancelGraceKey(String)
    case cancelGraceDevice(String)
    case clearReconnecting(String)
    case banner(String)
    case disconnect(String)
    case sync(GameState, includeAvatars: Bool)
  }

  static func steps(
    for message: NetworkMessage,
    peerKey: String,
    state: GameState,
    peers: PeerDirectory,
    reconnectingDeviceIds: Set<String>
  ) -> [Step] {
    switch message {
    case .hello(let playerId, let name, let avatar, let joinCode):
      return helloSteps(
        peerKey: peerKey,
        playerId: playerId,
        name: name,
        avatar: avatar,
        joinCode: joinCode,
        state: state,
        peers: peers,
        reconnectingDeviceIds: reconnectingDeviceIds
      )

    case .setName(let playerId, let name):
      guard owns(playerId, peerKey: peerKey, peers: peers, state: state) else { return [] }
      let next = GameEngine.updateName(playerId: playerId, name: name, in: state)
      return [.sync(next, includeAvatars: false)]

    case .setAvatar(let playerId, let avatar):
      guard owns(playerId, peerKey: peerKey, peers: peers, state: state) else { return [] }
      let next = GameEngine.updateAvatar(playerId: playerId, avatar: avatar, in: state)
      return [.sync(next, includeAvatars: false)]

    case .addPlayer(let playerId, let name):
      let peerDevice = peers.deviceId(for: peerKey)
      let next = GameEngine.addPlayer(
        id: playerId,
        name: name,
        deviceId: peerDevice,
        to: state
      )
      guard next != state else { return [] }
      return [.sync(next, includeAvatars: false)]

    case .removePlayer(let playerId):
      guard owns(playerId, peerKey: peerKey, peers: peers, state: state) else { return [] }
      let next = GameEngine.removePlayer(id: playerId, from: state)
      return [.sync(next, includeAvatars: false)]

    case .submitDrawing(let playerId, let drawing):
      guard owns(playerId, peerKey: peerKey, peers: peers, state: state) else { return [] }
      let next = GameEngine.submitDrawing(playerId: playerId, drawing: drawing, in: state)
      guard next != state else { return [] }
      return [.sync(next, includeAvatars: false)]

    case .submitGuess(let playerId, let text):
      guard owns(playerId, peerKey: peerKey, peers: peers, state: state) else { return [] }
      let next = GameEngine.submitGuess(playerId: playerId, text: text, in: state)
      guard next != state else { return [] }
      return [.sync(next, includeAvatars: false)]

    case .advanceReveal:
      // Only the host device advances reveal (local `advanceReveal()`).
      return []

    case .leave:
      return leaveSteps(peerKey: peerKey, state: state, peers: peers)

    case .syncState, .sessionEnded:
      return []
    }
  }

  static func departureBanner(deviceId: String, in state: GameState) -> String? {
    let names = state.players.filter { $0.deviceId == deviceId }.map(\.name)
    guard let name = names.first else { return nil }
    if state.phase == .lobby {
      return "\(name) left the lobby"
    }
    return "\(name) left — continuing without them"
  }

  private static func helloSteps(
    peerKey: String,
    playerId: String,
    name: String,
    avatar: Drawing,
    joinCode: String,
    state: GameState,
    peers: PeerDirectory,
    reconnectingDeviceIds: Set<String>
  ) -> [Step] {
    guard GamePartyLimits.normalizedJoinCode(joinCode) == state.joinCode,
          !state.joinCode.isEmpty else {
      return [.disconnect(peerKey)]
    }

    // Drop mid-round strangers (lobby-only joins).
    let isReturning = state.players.contains(where: { $0.deviceId == playerId })
    if !isReturning, state.phase != .lobby {
      return [.disconnect(peerKey)]
    }

    // Reject spoofed reclaim while another live connection still owns this device.
    if peers.hasLiveClaim(deviceId: playerId, except: peerKey) {
      let canReplace = reconnectingDeviceIds.contains(playerId)
        || state.absentDeviceIds.contains(playerId)
      guard canReplace else {
        return [.disconnect(peerKey)]
      }
    }

    if !isReturning, state.players.count >= GamePartyLimits.maxPlayers {
      return [.disconnect(peerKey)]
    }

    var steps: [Step] = [
      .bind(peerKey: peerKey, deviceId: playerId),
      .cancelGraceDevice(playerId),
      .clearReconnecting(playerId),
    ]

    if isReturning {
      var current = GameEngine.clearAbsent(deviceId: playerId, in: state)
      current = GameEngine.updateName(playerId: playerId, name: name, in: current)
      if !avatar.isEmpty {
        current = GameEngine.updateAvatar(playerId: playerId, avatar: avatar, in: current)
      }
      steps.append(.banner("\(GamePartyLimits.sanitizedName(name)) is back"))
      steps.append(.sync(current, includeAvatars: true))
      return steps
    }

    let next = GameEngine.addPlayer(
      id: playerId,
      name: name,
      deviceId: playerId,
      avatar: avatar,
      to: state
    )
    guard next != state else {
      steps.append(.disconnect(peerKey))
      return steps
    }
    steps.append(.sync(next, includeAvatars: false))
    return steps
  }

  private static func leaveSteps(
    peerKey: String,
    state: GameState,
    peers: PeerDirectory
  ) -> [Step] {
    let peerDevice = peers.deviceId(for: peerKey)
    var steps: [Step] = [.cancelGraceKey(peerKey)]
    if let bound = peers.boundDeviceId(for: peerKey) {
      steps.append(.clearReconnecting(bound))
    }
    if let banner = departureBanner(deviceId: peerDevice, in: state) {
      steps.append(.banner(banner))
    }
    let next = GameEngine.handleDisconnect(deviceId: peerDevice, from: state)
    steps.append(.unbind(peerKey))
    steps.append(.disconnect(peerKey))
    steps.append(.sync(next, includeAvatars: false))
    return steps
  }

  private static func owns(
    _ playerId: String,
    peerKey: String,
    peers: PeerDirectory,
    state: GameState
  ) -> Bool {
    state.player(id: playerId)?.deviceId == peers.deviceId(for: peerKey)
  }
}
