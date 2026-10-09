import Foundation
import Observation

/// Live party facade: lobby intents, one apply path, and transport wiring.
/// Inbound host messages are decided in `HostInbox`. Reconnect and host migration live in `SessionContinuity`.
@MainActor
@Observable
final class GameSession {
  static let serviceType = "doodleoop-game"
  static let avatarDefaultsKey = "doodleoop.avatar"

  private(set) var state: GameState?
  /// Mirrored from `state` so shell views can track phase without observing every sync.
  private(set) var phase: GamePhase?
  private(set) var role: Role = .idle
  private(set) var discoveredPeers: [DiscoveredPeer] = []
  private(set) var handoff: SeatHandoff?
  /// Joiner browse / connect progress for lobby UI.
  private(set) var joinStatus: JoinStatus = .idle
  /// One-shot alert shown after returning home or when the local network can't start.
  private(set) var alert: SessionAlert?
  /// Short in-game note (e.g. someone left). Cleared by the UI.
  private(set) var statusBanner: String?
  /// True while a joiner is in the disconnect grace window and trying to come back.
  private(set) var isReconnecting = false
  /// True while electing / seeking a new network host after the previous one dropped.
  private(set) var isMigratingHost = false
  /// Shown once after returning from background during a live game.
  private(set) var showStayInAppTip = false
  /// Remote devices currently inside the host's reconnect grace window.
  private(set) var reconnectingDeviceIds: Set<String> = []

  var localDisplayName: String
  private(set) var localAvatar: Drawing
  var draftCategory: String = ""

  let devicePlayerId: String
  private(set) var localPlayerId: String

  let historyStore: GameHistoryStore

  /// Join code for the active room (host-created, synced after join).
  var joinCode: String { state?.joinCode ?? rememberedJoinCode }

  private var transport: (any PartyTransport)?
  private var messageTransport: GameMessageTransport?
  private var peerDirectory = PeerDirectory()
  private let grace = DisconnectGrace()
  private let continuity = SessionContinuity()
  private var phaseTimerTask: Task<Void, Never>?
  private var backgroundedDuringGame = false
  /// Code the joiner entered (and keeps for reconnect hellos).
  private var rememberedJoinCode: String = ""

  enum Role: Equatable {
    case idle
    case host
    case joiner
  }

  var isHost: Bool { role == .host }

  /// Block drawing/guessing while reconnecting or transferring the host.
  var inputsFrozen: Bool {
    isMigratingHost || (isReconnecting && role == .joiner)
  }

  var localDeviceId: String { devicePlayerId }

  var hasSavedAvatar: Bool { !localAvatar.isEmpty }

  var localSeats: [Player] {
    state?.players.filter { $0.deviceId == devicePlayerId } ?? []
  }

  /// Per-phone connection chips for the in-game strip (host + joiners).
  var connectionPresences: [DeviceConnectionPresence] {
    guard let state else { return [] }
    let grouped = Dictionary(grouping: state.players, by: \.deviceId)
    return grouped.keys.sorted().compactMap { deviceId in
      guard let seats = grouped[deviceId], let first = seats.first else { return nil }
      let name: String
      if seats.count == 1 {
        name = first.name
      } else {
        name = seats.map(\.name).joined(separator: " · ")
      }
      let status: DeviceConnectionStatus
      if deviceId == devicePlayerId {
        status = .connected
      } else if reconnectingDeviceIds.contains(deviceId) {
        status = .reconnecting
      } else if state.absentDeviceIds.contains(deviceId) {
        status = .absent
      } else {
        status = .connected
      }
      return DeviceConnectionPresence(
        deviceId: deviceId,
        name: name,
        status: status,
        isLocal: deviceId == devicePlayerId
      )
    }
  }

  /// True when the connection strip should appear (reconnect/absent, or remotes mid-round).
  var showsConnectionStrip: Bool {
    guard role != .idle, state != nil else { return false }
    if isReconnecting || isMigratingHost { return true }
    if !reconnectingDeviceIds.isEmpty { return true }
    if let state, !state.absentDeviceIds.isEmpty { return true }
    // Host in-game: show remotes. Skip lobby when everyone is connected.
    if isHost, phase != nil, phase != .lobby {
      return connectionPresences.contains { !$0.isLocal }
    }
    return false
  }

  init(
    historyStore: GameHistoryStore = GameHistoryStore(),
    deviceId: String? = nil,
    defaults: UserDefaults = .standard
  ) {
    self.historyStore = historyStore
    let name = defaults.string(forKey: "displayName") ?? "Player"
    localDisplayName = name
    if defaults.string(forKey: "displayName") == nil {
      defaults.set(name, forKey: "displayName")
    }
    localAvatar = Self.loadAvatar(from: defaults)

    let id = deviceId ?? DeviceIdentity.current(defaults: defaults)
    devicePlayerId = id
    localPlayerId = id
    continuity.bind(ContinuityBridge(self))
  }

  static func loadAvatar(from defaults: UserDefaults) -> Drawing {
    guard let data = defaults.data(forKey: avatarDefaultsKey),
          let drawing = try? JSONDecoder().decode(Drawing.self, from: data),
          !drawing.isEmpty else {
      return .empty
    }
    return drawing
  }

  // MARK: - Lobby

  func hostGame() {
    leaveGame(clearState: true, notifyPeers: false)
    clearNotices()
    role = .host
    var lobby = GameState()
    lobby.roomId = UUID().uuidString
    lobby.networkHostDeviceId = devicePlayerId
    lobby.stateEpoch = 1
    lobby.joinCode = GamePartyLimits.makeJoinCode()
    rememberedJoinCode = lobby.joinCode
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
    attachHostTransport(resetPeers: true)
  }

  func startBrowsing() {
    leaveGame(clearState: true, notifyPeers: false)
    clearNotices()
    role = .joiner
    joinStatus = .browsing
    attachJoinerTransport()
  }

  /// Connect to a discovered host after the player enters the spoken join code.
  func join(_ peer: DiscoveredPeer, code: String) {
    guard role == .joiner else { return }
    let normalized = GamePartyLimits.normalizedJoinCode(code)
    guard normalized.count == GamePartyLimits.joinCodeLength else {
      joinStatus = .failed(message: SessionAlert.badJoinCode(peerName: peer.displayName).message)
      return
    }
    rememberedJoinCode = normalized
    joinStatus = .connecting(to: peer.displayName)
    transport?.connect(to: peer)
  }

  func clearAlert() {
    alert = nil
  }

  func clearStatusBanner() {
    statusBanner = nil
  }

  func clearStayInAppTip() {
    showStayInAppTip = false
  }

  func dismissJoinFailure() {
    if case .failed = joinStatus {
      joinStatus = .browsing
    }
  }

  /// Call from the root view when `scenePhase` changes.
  func handleLifecycle(_ lifecycle: AppLifecyclePhase) {
    switch lifecycle {
    case .background:
      if isInLiveGame {
        backgroundedDuringGame = true
      }
    case .active:
      guard backgroundedDuringGame else { return }
      backgroundedDuringGame = false
      guard isInLiveGame else { return }
      showStayInAppTip = true
      continuity.recoverAfterForeground()
    case .inactive:
      break
    }
  }

  private var isInLiveGame: Bool {
    role != .idle && (state != nil || isReconnecting || isMigratingHost)
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
    cancelAllDisconnectGrace()
    continuity.reset()
    reconnectingDeviceIds = []
    backgroundedDuringGame = false
    messageTransport?.disconnect()
    transport?.stop()
    transport = nil
    messageTransport = nil
    cancelPhaseTimer()
    discoveredPeers = []
    peerDirectory.removeAll()
    handoff = nil
    joinStatus = .idle
    role = .idle
    rememberedJoinCode = ""
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
    let trimmed = GamePartyLimits.sanitizedName(name, fallback: "")
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
    let seatName = GamePartyLimits.sanitizedName(name)
    guard var current = state, current.phase == .lobby else { return }
    guard current.players.count < GamePartyLimits.maxPlayers else { return }
    if isHost {
      let next = GameEngine.addPlayer(
        id: seatId,
        name: seatName,
        deviceId: devicePlayerId,
        to: current
      )
      guard next != current else { return }
      sync(next)
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
    // Stay discoverable so briefly backgrounded joiners can reconnect.
    transport?.refreshHosting(discoveryInfo: hostingDiscoveryInfo())
    prepareLocalHandoffIfNeeded()
  }

  func startNextTurn() {
    guard isHost, var current = state else { return }
    current = GameEngine.startNextTurn(in: current)
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
    // Reveal pacing is host-authoritative — joiners wait for syncState.
    guard isHost, var current = state else { return }
    current = GameEngine.advanceReveal(in: current)
    sync(current)
  }

  func returnToLobby() {
    guard isHost, var current = state else { return }
    current = GameEngine.returnToLobby(in: current)
    draftCategory = ""
    sync(current)
    transport?.refreshHosting(discoveryInfo: hostingDiscoveryInfo())
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
    case .reconnecting:
      role = .joiner
      localPlayerId = devicePlayerId
      replaceState(
        PreviewStateFactory.drawingState(
          devicePlayerId: devicePlayerId,
          displayName: localDisplayName,
          avatar: localAvatar
        )
      )
      isReconnecting = true
      isMigratingHost = false
    case .hostMigration:
      role = .joiner
      localPlayerId = devicePlayerId
      replaceState(
        PreviewStateFactory.drawingState(
          devicePlayerId: devicePlayerId,
          displayName: localDisplayName,
          avatar: localAvatar
        )
      )
      isMigratingHost = true
      isReconnecting = false
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

  private func clearNotices() {
    alert = nil
    statusBanner = nil
    showStayInAppTip = false
  }

  private func presentAlert(_ next: SessionAlert) {
    alert = next
  }

  private func endJoinerSession(reason: SessionAlert) {
    presentAlert(reason)
    leaveGame(clearState: true, notifyPeers: false)
  }

  private func attachHostTransport(resetPeers: Bool) {
    if resetPeers {
      peerDirectory.removeAll()
      reconnectingDeviceIds = []
    }
    let transport = NetworkPartyTransport(displayName: localDisplayName, serviceType: Self.serviceType)
    transport.delegate = self
    transport.startHosting(discoveryInfo: hostingDiscoveryInfo())
    self.transport = transport
    self.messageTransport = PartyMessageTransport(transport)
  }

  private func attachJoinerTransport() {
    let transport = NetworkPartyTransport(displayName: localDisplayName, serviceType: Self.serviceType)
    transport.delegate = self
    transport.startBrowsing()
    self.transport = transport
    self.messageTransport = PartyMessageTransport(transport)
  }

  private func hostingDiscoveryInfo() -> [String: String] {
    var info: [String: String] = ["host": localDisplayName]
    if let state {
      if !state.roomId.isEmpty {
        info["room"] = state.roomId
      }
      info["epoch"] = String(state.stateEpoch)
      if !state.networkHostDeviceId.isEmpty {
        info["hostDevice"] = state.networkHostDeviceId
      } else {
        info["hostDevice"] = devicePlayerId
      }
    } else {
      info["hostDevice"] = devicePlayerId
    }
    return info
  }

  private func sync(_ newState: GameState, includeAvatars: Bool = false) {
    applyState(newState)
    // Mid-round syncs omit avatar ink — joiners already have it from hello /
    // lobby sync. Rejoins and lobby/round-over keep full avatars.
    let payload: GameState
    if includeAvatars {
      payload = newState
    } else {
      switch newState.phase {
      case .lobby, .roundOver:
        payload = newState
      case .drawing, .guessing, .passing, .reveal:
        payload = newState.strippingAvatars()
      }
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
    if !merged.joinCode.isEmpty {
      rememberedJoinCode = merged.joinCode
    }
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

extension GameSession: PartyTransportDelegate {
  func transport(_ transport: any PartyTransport, didReceive data: Data, fromPeerKey peerKey: String) {
    guard let message = try? JSONDecoder().decode(NetworkMessage.self, from: data) else { return }
    handle(message, fromPeerKey: peerKey)
  }

  func transport(_ transport: any PartyTransport, peer peerKey: String, didChange state: PeerLinkState) {
    handlePeerChange(peerKey: peerKey, state: state)
  }

  func transport(_ transport: any PartyTransport, discoveredPeersDidChange peers: [DiscoveredPeer]) {
    discoveredPeers = peers
    continuity.peersChanged()
  }

  func transportDidFailToAdvertise(_ transport: any PartyTransport, error: Error) {
    presentAlert(
      .localNetwork(
        message: "Couldn't share this game on the local network. Check Settings → Doodleoop → Local Network, then try Create again."
      )
    )
  }

  func transportDidFailToBrowse(_ transport: any PartyTransport, error: Error) {
    joinStatus = .failed(
      message: "Couldn't look for nearby games. Check Settings → Doodleoop → Local Network, then try Join again."
    )
  }

  private func handle(_ message: NetworkMessage, fromPeerKey peerKey: String) {
    switch role {
    case .host:
      applyHostInbox(message, fromPeerKey: peerKey)
    case .joiner:
      switch message {
      case .syncState(let gameState):
        if let current = state, gameState.stateEpoch < current.stateEpoch {
          // Stale host — ignore.
          return
        }
        applyState(gameState)
        joinStatus = .idle
        if continuity.noteLinkRestored() {
          statusBanner = "Reconnected"
        }
        prepareLocalHandoffIfNeeded()
      case .sessionEnded:
        endJoinerSession(reason: .hostEndedGame)
      default:
        break
      }
    case .idle:
      break
    }
  }

  private func applyHostInbox(_ message: NetworkMessage, fromPeerKey peerKey: String) {
    guard let current = state else { return }
    let steps = HostInbox.steps(
      for: message,
      peerKey: peerKey,
      state: current,
      peers: peerDirectory,
      reconnectingDeviceIds: reconnectingDeviceIds
    )
    for step in steps {
      switch step {
      case .bind(let key, let deviceId):
        peerDirectory.bind(key, to: deviceId)
      case .unbind(let key):
        peerDirectory.unbind(key)
      case .cancelGraceKey(let key):
        grace.cancel(key: key)
      case .cancelGraceDevice(let deviceId):
        for key in peerDirectory.keys(for: deviceId) {
          grace.cancel(key: key)
        }
      case .clearReconnecting(let deviceId):
        reconnectingDeviceIds.remove(deviceId)
      case .banner(let text):
        statusBanner = text
      case .disconnect(let key):
        transport?.disconnectPeer(key)
      case .sync(let next, let includeAvatars):
        sync(next, includeAvatars: includeAvatars)
      }
    }
  }

  private func handlePeerChange(peerKey: String, state linkState: PeerLinkState) {
    switch linkState {
    case .connected:
      if role == .joiner {
        // Stay `.connecting` until the first syncState so a rejected join code
        // still surfaces as a join failure instead of a silent drop.
        cancelDisconnectGrace(key: "host")
        send(
          .hello(
            playerId: devicePlayerId,
            name: localDisplayName,
            avatar: localAvatar,
            joinCode: rememberedJoinCode
          )
        )
      } else if role == .host {
        cancelDisconnectGrace(key: peerKey)
      }
    case .notConnected:
      if role == .joiner {
        handleJoinerDisconnect(peerKey: peerKey)
      } else if role == .host, state != nil {
        beginHostPeerGrace(peerKey: peerKey)
      }
    }
  }

  /// Failed first-time connect → stay browsing. Live game → grace + reconnect attempt.
  private func handleJoinerDisconnect(peerKey: String) {
    if case .connecting(let name) = joinStatus {
      joinStatus = .failed(
        message: SessionAlert.joinFailed(peerName: name).message
      )
      return
    }
    guard state != nil else { return }
    continuity.beginJoinerReconnect()
  }

  private func beginHostPeerGrace(peerKey: String) {
    let peerDevice = peerDirectory.deviceId(for: peerKey)
    // Unknown connection that never said hello — drop quietly.
    guard peerDirectory.boundDeviceId(for: peerKey) != nil
      || state?.players.contains(where: { $0.deviceId == peerDevice }) == true else {
      peerDirectory.unbind(peerKey)
      return
    }
    let name = state?.players.first { $0.deviceId == peerDevice }?.name ?? "Player"
    reconnectingDeviceIds.insert(peerDevice)
    statusBanner = "Waiting for \(name) to reconnect…"
    scheduleDisconnectGrace(key: peerKey) { [weak self] in
      self?.finalizeHostPeerLoss(peerKey: peerKey)
    }
  }

  private func finalizeHostPeerLoss(peerKey: String) {
    guard role == .host, var current = state else { return }
    let peerDevice = peerDirectory.deviceId(for: peerKey)
    reconnectingDeviceIds.remove(peerDevice)
    if let banner = HostInbox.departureBanner(deviceId: peerDevice, in: current) {
      statusBanner = banner
    }
    current = GameEngine.handleDisconnect(deviceId: peerDevice, from: current)
    peerDirectory.unbind(peerKey)
    sync(current)
  }

  private func scheduleDisconnectGrace(key: String, action: @escaping @MainActor () -> Void) {
    grace.schedule(key: key, action: action)
  }

  private func cancelDisconnectGrace(key: String) {
    grace.cancel(key: key)
  }

  private func cancelAllDisconnectGrace() {
    grace.cancelAll()
  }
}

extension GameSession {
  /// Retained by `SessionContinuity`. Holds the session unowned so the two don't cycle.
  final class ContinuityBridge: SessionContinuityContext {
    unowned let session: GameSession

    init(_ session: GameSession) {
      self.session = session
    }

    var role: Role { session.role }
    var state: GameState? { session.state }
    var devicePlayerId: String { session.devicePlayerId }
    var discoveredPeers: [DiscoveredPeer] { session.discoveredPeers }
    var isReconnecting: Bool { session.isReconnecting }
    var isMigratingHost: Bool { session.isMigratingHost }
    var hasTransport: Bool { session.transport != nil }
    var keepsInjectedTransport: Bool { session.messageTransport is RecordingMessageTransport }

    func setRole(_ role: Role) { session.role = role }
    func setReconnecting(_ value: Bool) { session.isReconnecting = value }
    func setMigratingHost(_ value: Bool) { session.isMigratingHost = value }
    func setStatusBanner(_ value: String?) { session.statusBanner = value }
    func setHandoff(_ value: SeatHandoff?) { session.handoff = value }

    func applyState(_ newState: GameState) { session.applyState(newState) }
    func sync(_ newState: GameState, includeAvatars: Bool) {
      session.sync(newState, includeAvatars: includeAvatars)
    }
    func endJoinerSession(reason: SessionAlert) { session.endJoinerSession(reason: reason) }
    func attachHostTransport(resetPeers: Bool) { session.attachHostTransport(resetPeers: resetPeers) }
    func attachJoinerTransport() { session.attachJoinerTransport() }
    func cancelPhaseTimer() { session.cancelPhaseTimer() }
    func schedulePhaseTimer() { session.schedulePhaseTimer() }
    func prepareLocalHandoffIfNeeded() { session.prepareLocalHandoffIfNeeded() }
    func scheduleDisconnectGrace(key: String, action: @escaping @MainActor () -> Void) {
      session.scheduleDisconnectGrace(key: key, action: action)
    }
    func cancelDisconnectGrace(key: String) { session.cancelDisconnectGrace(key: key) }
    func refreshHostingAdvertisement() {
      session.transport?.refreshHosting(discoveryInfo: session.hostingDiscoveryInfo())
    }
    func ensureBrowsingAlongsideHosting() { session.transport?.ensureBrowsingAlongsideHosting() }
    func ensureBrowsing() { session.transport?.ensureBrowsing() }
    func connect(to peer: DiscoveredPeer) { session.transport?.connect(to: peer) }
    func tearDownTransport() {
      session.messageTransport?.disconnect()
      session.transport?.stop()
      session.transport = nil
      session.messageTransport = nil
    }
    func clearPeerBook() {
      session.peerDirectory.removeAll()
      session.reconnectingDeviceIds = []
    }
  }
}

#if DEBUG
extension GameSession {
  /// Test seam: set role/state without a live transport.
  func testing_configure(
    role: Role,
    state: GameState?,
    localPlayerId: String? = nil,
    peerDeviceIds: [String: String] = [:],
    messageTransport: GameMessageTransport? = nil,
    joinStatus: JoinStatus = .idle,
    disconnectGraceSeconds: TimeInterval? = nil
  ) {
    self.role = role
    self.state = state
    self.phase = state?.phase
    self.peerDirectory = PeerDirectory(deviceIds: peerDeviceIds)
    self.messageTransport = messageTransport
    self.joinStatus = joinStatus
    if let disconnectGraceSeconds {
      grace.seconds = disconnectGraceSeconds
    }
    if let localPlayerId {
      self.localPlayerId = localPlayerId
    }
  }

  func testing_handle(_ message: NetworkMessage, fromPeerKey peerKey: String) {
    handle(message, fromPeerKey: peerKey)
  }

  func testing_peerChange(peerKey: String, state linkState: PeerLinkState) {
    handlePeerChange(peerKey: peerKey, state: linkState)
  }

  func testing_expireDisconnectGrace(for peerKey: String) {
    cancelDisconnectGrace(key: peerKey)
    if role == .host {
      finalizeHostPeerLoss(peerKey: peerKey)
    } else if role == .joiner {
      if peerKey == "migration" {
        continuity.migrationTimedOut()
      } else {
        continuity.attemptHostMigrationAfterHostLoss()
      }
    }
  }

  func testing_attemptHostMigration() {
    continuity.attemptHostMigrationAfterHostLoss()
  }

  func testing_promoteToNetworkHost(previousHostDeviceId: String) {
    continuity.promoteToNetworkHost(previousHostDeviceId: previousHostDeviceId)
  }

  var testing_isMigratingHost: Bool { isMigratingHost }

  func testing_handleLifecycle(_ phase: AppLifecyclePhase) {
    handleLifecycle(phase)
  }

  var testing_messageTransport: GameMessageTransport? { messageTransport }

  func testing_handlePhaseExpired() {
    handlePhaseExpired()
  }

  func testing_prepareLocalHandoffIfNeeded() {
    prepareLocalHandoffIfNeeded()
  }
}
#endif
