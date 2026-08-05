import Foundation
import MultipeerConnectivity
import Combine
import Observation

@MainActor
@Observable
final class GameSession {
  static let serviceType = "doodleoop-game"
  static let avatarDefaultsKey = "doodleoop.avatar"

  private(set) var state: GameState?
  /// Mirrored from `state` so shell views can track phase without observing every sync.
  private(set) var phase: GamePhase?
  private(set) var role: Role = .idle
  private(set) var discoveredPeers: [MCPeerID] = []
  private(set) var handoff: SeatHandoff?

  var localDisplayName: String
  private(set) var localAvatar: Drawing
  var draftCategory: String = ""

  let devicePlayerId: String
  private(set) var localPlayerId: String

  let historyStore: GameHistoryStore

  private var transport: MultipeerTransport?
  private var messageTransport: GameMessageTransport?
  private var peerDeviceIds: [String: String] = [:]
  private var cancellables = Set<AnyCancellable>()
  private var phaseTimerTask: Task<Void, Never>?

  enum Role: Equatable {
    case idle
    case host
    case joiner
  }

  var isHost: Bool { role == .host }

  var localDeviceId: String { devicePlayerId }

  var hasSavedAvatar: Bool { !localAvatar.isEmpty }

  var localSeats: [Player] {
    state?.players.filter { $0.deviceId == devicePlayerId } ?? []
  }

  init(historyStore: GameHistoryStore = GameHistoryStore()) {
    self.historyStore = historyStore
    let defaults = UserDefaults.standard
    let name = defaults.string(forKey: "displayName") ?? "Player"
    localDisplayName = name
    if defaults.string(forKey: "displayName") == nil {
      defaults.set(name, forKey: "displayName")
    }
    localAvatar = Self.loadAvatar(from: defaults)

    let id = DeviceIdentity.current()
    devicePlayerId = id
    localPlayerId = id
  }

  private static func loadAvatar(from defaults: UserDefaults) -> Drawing {
    guard let data = defaults.data(forKey: avatarDefaultsKey),
          let drawing = try? JSONDecoder().decode(Drawing.self, from: data),
          !drawing.isEmpty else {
      return .empty
    }
    return drawing
  }

  // MARK: - Lobby

  func hostGame() {
    leaveGame(clearState: true)
    role = .host
    var lobby = GameState()
    lobby = GameEngine.addPlayer(
      id: devicePlayerId,
      name: localDisplayName,
      deviceId: devicePlayerId,
      avatar: localAvatar,
      to: lobby
    )
    state = lobby
    phase = lobby.phase
    localPlayerId = devicePlayerId

    let transport = MultipeerTransport(displayName: localDisplayName, serviceType: Self.serviceType)
    transport.delegate = self
    transport.startHosting(discoveryInfo: ["host": localDisplayName])
    self.transport = transport
    self.messageTransport = MultipeerMessageTransport(transport)
    bindPeers(transport)
  }

  func startBrowsing() {
    leaveGame(clearState: true)
    role = .joiner
    let transport = MultipeerTransport(displayName: localDisplayName, serviceType: Self.serviceType)
    transport.delegate = self
    transport.startBrowsing()
    self.transport = transport
    self.messageTransport = MultipeerMessageTransport(transport)
    bindPeers(transport)
  }

  func join(_ peer: MCPeerID) {
    transport?.invite(peer)
  }

  func leaveGame(clearState: Bool = true, notifyPeers: Bool = true) {
    // Broadcast before tearing down so peers can exit cleanly.
    if notifyPeers {
      if role == .host {
        send(.sessionEnded)
      } else if role == .joiner {
        send(.leave)
      }
    }
    messageTransport?.disconnect()
    transport?.disconnect()
    transport = nil
    messageTransport = nil
    cancellables.removeAll()
    cancelPhaseTimer()
    discoveredPeers = []
    peerDeviceIds = [:]
    handoff = nil
    role = .idle
    if clearState {
      state = nil
      phase = nil
    } else {
      phase = state?.phase
    }
  }

  func updateGameSettings(drawSeconds: Int, guessSeconds: Int, maxRounds: Int? = nil) {
    guard isHost, var current = state else { return }
    current = GameEngine.updateSettings(
      drawTimeLimitSeconds: drawSeconds,
      guessTimeLimitSeconds: guessSeconds,
      maxRounds: maxRounds,
      in: current
    )
    sync(current)
  }

  func updateDisplayName(_ name: String) {
    let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
    guard !trimmed.isEmpty else { return }
    localDisplayName = trimmed
    UserDefaults.standard.set(trimmed, forKey: "displayName")
    guard var current = state else { return }
    if isHost {
      current = GameEngine.updateName(playerId: devicePlayerId, name: trimmed, in: current)
      sync(current)
    } else {
      send(.setName(playerId: devicePlayerId, name: trimmed))
    }
  }

  func updateAvatar(_ drawing: Drawing) {
    guard !drawing.isEmpty else { return }
    localAvatar = drawing
    if let data = try? JSONEncoder().encode(drawing) {
      UserDefaults.standard.set(data, forKey: Self.avatarDefaultsKey)
    }
    guard var current = state else { return }
    if isHost {
      current = GameEngine.updateAvatar(playerId: devicePlayerId, avatar: drawing, in: current)
      sync(current)
    } else {
      send(.setAvatar(playerId: devicePlayerId, avatar: drawing))
    }
  }

  func addLocalSeat(name: String) {
    let seatId = UUID().uuidString
    let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
    let seatName = trimmed.isEmpty ? "Player" : trimmed
    guard var current = state, current.phase == .lobby else { return }
    if isHost {
      current = GameEngine.addPlayer(
        id: seatId,
        name: seatName,
        deviceId: devicePlayerId,
        to: current
      )
      sync(current)
    } else {
      send(.addPlayer(playerId: seatId, name: seatName))
    }
  }

  func removeLocalSeat(_ playerId: String) {
    guard playerId != devicePlayerId else { return }
    guard var current = state,
          let player = current.player(id: playerId),
          player.deviceId == devicePlayerId else { return }
    if isHost {
      current = GameEngine.removePlayer(id: playerId, from: current)
      sync(current)
    } else {
      send(.removePlayer(playerId: playerId))
    }
  }

  /// Host removes any non-host seat from the lobby.
  func removeLobbyPlayer(_ playerId: String) {
    guard isHost, var current = state, current.phase == .lobby else { return }
    guard playerId != current.hostId else { return }
    current = GameEngine.removePlayer(id: playerId, from: current)
    sync(current)
  }

  func startRound() {
    guard isHost, var current = state else { return }
    current = GameEngine.startRound(category: draftCategory, in: current)
    sync(current)
    prepareLocalHandoffIfNeeded()
  }

  func submitDrawing(_ drawing: Drawing) {
    guard var current = state else { return }
    if isHost {
      current = GameEngine.submitDrawing(playerId: localPlayerId, drawing: drawing, in: current)
      sync(current)
      prepareLocalHandoffIfNeeded()
    } else {
      send(.submitDrawing(playerId: localPlayerId, drawing: drawing))
    }
  }

  func submitGuess(_ text: String) {
    guard var current = state else { return }
    if isHost {
      current = GameEngine.submitGuess(playerId: localPlayerId, text: text, in: current)
      sync(current)
      prepareLocalHandoffIfNeeded()
    } else {
      send(.submitGuess(playerId: localPlayerId, text: text))
    }
  }

  func advanceReveal() {
    guard var current = state else { return }
    if isHost {
      current = GameEngine.advanceReveal(in: current)
      sync(current)
    } else {
      send(.advanceReveal)
    }
  }

  func returnToLobby() {
    guard isHost, var current = state else { return }
    current = GameEngine.returnToLobby(in: current)
    draftCategory = ""
    sync(current)
  }

  func confirmHandoff() {
    handoff = nil
  }

  func switchActiveSeat(to playerId: String) {
    guard localSeats.contains(where: { $0.id == playerId }) else { return }
    localPlayerId = playerId
  }

  // MARK: - View previews

  func loadPreview(_ preview: ViewPreview) {
    leaveGame()
    handoff = nil
    discoveredPeers = []

    switch preview {
    case .avatarSetup, .paperStyles:
      return
    case .lobbyPassAndPlay:
      role = .host
      localPlayerId = devicePlayerId
      replaceState(previewLobby(playerCount: 4, sharedDevice: true))
      draftCategory = "Breakfast foods"
    case .lobbyNearbyHost:
      role = .host
      localPlayerId = devicePlayerId
      replaceState(previewLobby(playerCount: 5, sharedDevice: false))
      draftCategory = "Things with wings"
    case .lobbyNearbyJoiner:
      role = .joiner
      localPlayerId = devicePlayerId
      replaceState(nil)
    case .lobbyNearbyGameFound:
      role = .joiner
      localPlayerId = devicePlayerId
      replaceState(nil)
      discoveredPeers = [PreviewStateFactory.discoveredDemoPeer()]
    case .drawing:
      role = .host
      localPlayerId = devicePlayerId
      replaceState(
        PreviewStateFactory.drawingState(
          devicePlayerId: devicePlayerId,
          displayName: localDisplayName,
          avatar: localAvatar
        )
      )
    case .drawingFromGuess:
      role = .host
      localPlayerId = devicePlayerId
      replaceState(
        PreviewStateFactory.drawingFromGuessState(
          devicePlayerId: devicePlayerId,
          displayName: localDisplayName,
          avatar: localAvatar
        )
      )
    case .guessing:
      role = .host
      localPlayerId = devicePlayerId
      replaceState(
        PreviewStateFactory.guessingState(
          devicePlayerId: devicePlayerId,
          displayName: localDisplayName,
          avatar: localAvatar
        )
      )
    case .reveal:
      role = .host
      localPlayerId = devicePlayerId
      replaceState(
        PreviewStateFactory.revealState(
          devicePlayerId: devicePlayerId,
          displayName: localDisplayName,
          avatar: localAvatar
        )
      )
    case .roundOver:
      role = .host
      localPlayerId = devicePlayerId
      replaceState(
        PreviewStateFactory.roundOverState(
          devicePlayerId: devicePlayerId,
          displayName: localDisplayName,
          avatar: localAvatar
        )
      )
    case .handoffOverlay:
      role = .host
      localPlayerId = devicePlayerId
      let players = PreviewStateFactory.makePlayers(
        count: 3,
        sharedDevice: true,
        devicePlayerId: devicePlayerId,
        displayName: localDisplayName,
        avatar: localAvatar
      )
      var next = PreviewStateFactory.makeLobby(players: players)
      next = GameEngine.startRound(category: "Breakfast foods", in: next)
      replaceState(next)
      if let nextPlayer = players.dropFirst().first {
        localPlayerId = nextPlayer.id
        handoff = SeatHandoff(
          playerId: nextPlayer.id,
          title: "Pass the phone",
          message: "Hand the phone to \(nextPlayer.name) so they can draw."
        )
      }
    }
  }

  private func previewLobby(playerCount: Int, sharedDevice: Bool) -> GameState {
    PreviewStateFactory.makeLobby(
      playerCount: playerCount,
      sharedDevice: sharedDevice,
      devicePlayerId: devicePlayerId,
      displayName: localDisplayName,
      avatar: localAvatar
    )
  }

  // MARK: - Internals

  private func replaceState(_ newState: GameState?) {
    state = newState
    phase = newState?.phase
  }

  private func bindPeers(_ transport: MultipeerTransport) {
    transport.$discoveredPeers
      .receive(on: DispatchQueue.main)
      .sink { [weak self] peers in
        self?.discoveredPeers = peers
      }
      .store(in: &cancellables)
  }

  private func sync(_ newState: GameState) {
    applyState(newState)
    // Mid-round syncs omit avatar ink — joiners already have it from hello /
    // lobby sync. Lobby and round-over keep full avatars for the player list.
    let payload: GameState
    switch newState.phase {
    case .lobby, .roundOver:
      payload = newState
    case .drawing, .guessing, .reveal:
      payload = newState.strippingAvatars()
    }
    send(.syncState(payload))
  }

  private func applyState(_ newState: GameState) {
    var merged = newState
    if let previous = state {
      merged.players = newState.players.map { player in
        guard player.avatar.isEmpty,
              let prior = previous.player(id: player.id),
              !prior.avatar.isEmpty else { return player }
        var restored = player
        restored.avatar = prior.avatar
        return restored
      }
    }
    state = merged
    if phase != merged.phase {
      phase = merged.phase
    }
    historyStore.saveIfNeeded(from: merged)
    schedulePhaseTimer()
  }

  private func cancelPhaseTimer() {
    phaseTimerTask?.cancel()
    phaseTimerTask = nil
  }

  /// Host waits for `phaseEndsAt`, then force-advances anyone who never submitted.
  /// Slight delay after the deadline lets in-flight auto-submits land first.
  private func schedulePhaseTimer() {
    cancelPhaseTimer()
    guard isHost,
          let current = state,
          current.phase == .drawing || current.phase == .guessing,
          let endsAt = current.phaseEndsAt else { return }

    let delay = max(0, endsAt.timeIntervalSinceNow) + 0.75
    phaseTimerTask = Task { [weak self] in
      let nanoseconds = UInt64(delay * 1_000_000_000)
      try? await Task.sleep(nanoseconds: nanoseconds)
      guard !Task.isCancelled else { return }
      await self?.handlePhaseExpired()
    }
  }

  private func handlePhaseExpired() {
    guard isHost, var current = state else { return }
    let previous = current
    current = GameEngine.expireTurn(in: current)
    guard current != previous else { return }
    sync(current)
    prepareLocalHandoffIfNeeded()
  }

  private func send(_ message: NetworkMessage) {
    messageTransport?.send(message)
  }

  private func prepareLocalHandoffIfNeeded() {
    guard let current = state else { return }
    guard current.phase == .drawing || current.phase == .guessing else {
      handoff = nil
      return
    }

    let pending = localSeats.filter { !current.submittedPlayerIds.contains($0.id) }
    guard let next = pending.first else {
      handoff = nil
      return
    }

    if localPlayerId != next.id || localSeats.count > 1 {
      localPlayerId = next.id
      let verb = current.phase == .drawing ? "draw" : "guess"
      handoff = SeatHandoff(
        playerId: next.id,
        title: "Pass the phone",
        message: "Hand the phone to \(next.name) so they can \(verb)."
      )
    }
  }
}

extension GameSession: MultipeerTransportDelegate {
  nonisolated func transport(_ transport: MultipeerTransport, didReceive data: Data, from peerID: MCPeerID) {
    let peerName = peerID.displayName
    Task { @MainActor in
      guard let message = try? JSONDecoder().decode(NetworkMessage.self, from: data) else { return }
      handle(message, fromPeerNamed: peerName)
    }
  }

  nonisolated func transport(
    _ transport: MultipeerTransport,
    peer peerID: MCPeerID,
    didChange state: MCSessionState
  ) {
    let peerName = peerID.displayName
    Task { @MainActor in
      handlePeerChange(named: peerName, state: state)
    }
  }

  nonisolated func transport(
    _ transport: MultipeerTransport,
    foundPeer peerID: MCPeerID,
    discoveryInfo: [String: String]?
  ) {}

  nonisolated func transport(_ transport: MultipeerTransport, lostPeer peerID: MCPeerID) {}

  @MainActor
  private func handle(_ message: NetworkMessage, fromPeerNamed peerName: String) {
    switch role {
    case .host:
      handleHost(message, fromPeerNamed: peerName)
    case .joiner:
      switch message {
      case .syncState(let gameState):
        applyState(gameState)
        prepareLocalHandoffIfNeeded()
      case .sessionEnded:
        leaveGame(clearState: true, notifyPeers: false)
      default:
        break
      }
    case .idle:
      break
    }
  }

  @MainActor
  private func handleHost(_ message: NetworkMessage, fromPeerNamed peerName: String) {
    guard var current = state else { return }
    let peerDevice = peerDeviceIds[peerName] ?? peerName

    switch message {
    case .hello(let playerId, let name, let avatar):
      peerDeviceIds[peerName] = playerId
      current = GameEngine.addPlayer(
        id: playerId,
        name: name,
        deviceId: playerId,
        avatar: avatar,
        to: current
      )
      sync(current)

    case .setName(let playerId, let name):
      guard owns(playerId, peerDevice: peerDevice, in: current) else { return }
      current = GameEngine.updateName(playerId: playerId, name: name, in: current)
      sync(current)

    case .setAvatar(let playerId, let avatar):
      guard owns(playerId, peerDevice: peerDevice, in: current) else { return }
      current = GameEngine.updateAvatar(playerId: playerId, avatar: avatar, in: current)
      sync(current)

    case .addPlayer(let playerId, let name):
      current = GameEngine.addPlayer(
        id: playerId,
        name: name,
        deviceId: peerDevice,
        to: current
      )
      sync(current)

    case .removePlayer(let playerId):
      guard owns(playerId, peerDevice: peerDevice, in: current) else { return }
      current = GameEngine.removePlayer(id: playerId, from: current)
      sync(current)

    case .submitDrawing(let playerId, let drawing):
      guard owns(playerId, peerDevice: peerDevice, in: current) else { return }
      current = GameEngine.submitDrawing(playerId: playerId, drawing: drawing, in: current)
      sync(current)

    case .submitGuess(let playerId, let text):
      guard owns(playerId, peerDevice: peerDevice, in: current) else { return }
      current = GameEngine.submitGuess(playerId: playerId, text: text, in: current)
      sync(current)

    case .advanceReveal:
      current = GameEngine.advanceReveal(in: current)
      sync(current)

    case .leave:
      current = GameEngine.handleDisconnect(deviceId: peerDevice, from: current)
      sync(current)

    case .syncState, .sessionEnded:
      break
    }
  }

  @MainActor
  private func handlePeerChange(named peerName: String, state sessionState: MCSessionState) {
    switch sessionState {
    case .connected:
      if role == .joiner {
        send(.hello(playerId: devicePlayerId, name: localDisplayName, avatar: localAvatar))
      }
    case .notConnected:
      if role == .joiner {
        // Host (or session) dropped — don't leave joiners stuck mid-round.
        leaveGame(clearState: true, notifyPeers: false)
      } else if role == .host, var current = self.state {
        let peerDevice = peerDeviceIds[peerName] ?? peerName
        current = GameEngine.handleDisconnect(deviceId: peerDevice, from: current)
        peerDeviceIds[peerName] = nil
        sync(current)
      }
    default:
      break
    }
  }

  private func owns(_ playerId: String, peerDevice: String, in state: GameState) -> Bool {
    state.player(id: playerId)?.deviceId == peerDevice
  }
}

#if DEBUG
extension GameSession {
  /// Test seam: set role/state without Multipeer.
  func testing_configure(
    role: Role,
    state: GameState?,
    localPlayerId: String? = nil,
    peerDeviceIds: [String: String] = [:],
    messageTransport: GameMessageTransport? = nil
  ) {
    self.role = role
    self.state = state
    self.phase = state?.phase
    self.peerDeviceIds = peerDeviceIds
    self.messageTransport = messageTransport
    if let localPlayerId {
      self.localPlayerId = localPlayerId
    }
  }

  func testing_handle(_ message: NetworkMessage, fromPeerNamed peerName: String) {
    handle(message, fromPeerNamed: peerName)
  }

  func testing_peerChange(named peerName: String, state sessionState: MCSessionState) {
    handlePeerChange(named: peerName, state: sessionState)
  }

  var testing_messageTransport: GameMessageTransport? { messageTransport }
}
#endif
