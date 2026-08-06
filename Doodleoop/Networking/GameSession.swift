import Foundation
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

  private var transport: (any PartyTransport)?
  private var messageTransport: GameMessageTransport?
  /// Transport peer key → durable `deviceId`.
  private var peerDeviceIds: [String: String] = [:]
  private var phaseTimerTask: Task<Void, Never>?
  private var disconnectGraceTasks: [String: Task<Void, Never>] = [:]
  private var backgroundedDuringGame = false
  /// How long to wait for a peer to return before treating the drop as final.
  private var disconnectGraceSeconds: TimeInterval = 15
  /// Prior network host while seeking a migrated successor.
  private var migrationPreviousHostDeviceId: String?

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
    // Host in-game: show remotes. Skip lobby so we don't cover LeaveToolbarBand.
    if isHost, phase != nil, phase != .lobby {
      return connectionPresences.contains { !$0.isLocal }
    }
    return false
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
    leaveGame(clearState: true, notifyPeers: false)
    clearNotices()
    role = .host
    var lobby = GameState()
    lobby.roomId = UUID().uuidString
    lobby.networkHostDeviceId = devicePlayerId
    lobby.stateEpoch = 1
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

  func join(_ peer: DiscoveredPeer) {
    guard role == .joiner else { return }
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
      recoverAfterForeground()
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
    isReconnecting = false
    isMigratingHost = false
    migrationPreviousHostDeviceId = nil
    reconnectingDeviceIds = []
    backgroundedDuringGame = false
    messageTransport?.disconnect()
    transport?.stop()
    transport = nil
    messageTransport = nil
    cancelPhaseTimer()
    discoveredPeers = []
    peerDeviceIds = [:]
    handoff = nil
    joinStatus = .idle
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
    // Stay discoverable so briefly backgrounded joiners can reconnect.
    transport?.refreshHosting(discoveryInfo: hostingDiscoveryInfo())
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
      peerDeviceIds = [:]
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

  private func recoverAfterForeground() {
    if role == .host, state != nil {
      // Local peer links often die in background — keep advertising for rejoins.
      if transport == nil {
        attachHostTransport(resetPeers: false)
      } else {
        transport?.refreshHosting(discoveryInfo: hostingDiscoveryInfo())
      }
      // Watch for a successor that took over while we were offline.
      transport?.ensureBrowsingAlongsideHosting()
      considerYieldingToSuccessorHost()
      schedulePhaseTimer()
    } else if role == .joiner, state != nil {
      beginJoinerReconnect()
    }
  }

  private func beginJoinerReconnect() {
    let alreadyReconnecting = isReconnecting || isMigratingHost
    isReconnecting = true
    statusBanner = "Connection lost — trying to reconnect…"
    if transport == nil {
      attachJoinerTransport()
    } else {
      transport?.ensureBrowsing()
    }
    connectDiscoveredPeersForReconnect()
    if !alreadyReconnecting {
      scheduleDisconnectGrace(key: "host") { [weak self] in
        self?.attemptHostMigrationAfterHostLoss()
      }
    }
  }

  private func connectDiscoveredPeersForReconnect() {
    guard role == .joiner else { return }
    for peer in peersRelevantForReconnect() {
      transport?.connect(to: peer)
    }
  }

  private func peersRelevantForReconnect() -> [DiscoveredPeer] {
    guard let state else { return discoveredPeers }
    let room = state.roomId
    if isMigratingHost {
      let previous = migrationPreviousHostDeviceId ?? state.networkHostDeviceId
      return discoveredPeers.filter { peer in
        guard peer.roomId == room || (room.isEmpty && peer.roomId == nil) else { return false }
        if let hostDevice = peer.hostDeviceId, !previous.isEmpty {
          return hostDevice != previous
        }
        return (peer.epoch ?? 0) > state.stateEpoch
      }
    }
    if room.isEmpty {
      return discoveredPeers
    }
    let sameRoom = discoveredPeers.filter { $0.roomId == room || $0.roomId == nil }
    return sameRoom.isEmpty ? discoveredPeers : sameRoom
  }

  /// After reconnect grace, elect a new network host among remaining phones.
  private func attemptHostMigrationAfterHostLoss() {
    guard role == .joiner, var current = state else {
      isReconnecting = false
      endJoinerSession(reason: .lostConnection)
      return
    }

    let previousHost = current.networkHostDeviceId.isEmpty
      ? (migrationPreviousHostDeviceId ?? "")
      : current.networkHostDeviceId
    migrationPreviousHostDeviceId = previousHost.isEmpty ? nil : previousHost

    if !previousHost.isEmpty, previousHost != devicePlayerId {
      current = GameEngine.handleDisconnect(deviceId: previousHost, from: current)
    }
    // Keep seats for devices still here — we're present.
    current = GameEngine.clearAbsent(deviceId: devicePlayerId, in: current)
    applyState(current)

    guard let winner = GameEngine.electedNetworkHostDeviceId(in: current) else {
      isReconnecting = false
      isMigratingHost = false
      endJoinerSession(reason: .lostConnection)
      return
    }

    if winner == devicePlayerId {
      promoteToNetworkHost(previousHostDeviceId: previousHost)
    } else {
      beginSeekingMigratedHost()
    }
  }

  private func promoteToNetworkHost(previousHostDeviceId: String) {
    guard var current = state else { return }
    isMigratingHost = true
    isReconnecting = false
    cancelDisconnectGrace(key: "host")
    cancelDisconnectGrace(key: "migration")

    if !previousHostDeviceId.isEmpty {
      current = GameEngine.handleDisconnect(deviceId: previousHostDeviceId, from: current)
    }
    current = GameEngine.clearAbsent(deviceId: devicePlayerId, in: current)
    current = GameEngine.claimNetworkHost(deviceId: devicePlayerId, in: current)

    role = .host
    handoff = nil
    applyState(current)
    // Unit tests inject RecordingMessageTransport — keep it instead of opening Bonjour.
    if messageTransport is RecordingMessageTransport {
      peerDeviceIds = [:]
      reconnectingDeviceIds = []
    } else {
      messageTransport?.disconnect()
      transport?.stop()
      transport = nil
      messageTransport = nil
      attachHostTransport(resetPeers: true)
    }

    sync(current, includeAvatars: true)
    isMigratingHost = false
    migrationPreviousHostDeviceId = nil
    statusBanner = "You're hosting now"
    prepareLocalHandoffIfNeeded()
  }

  private func beginSeekingMigratedHost() {
    isMigratingHost = true
    isReconnecting = true
    statusBanner = "Finding a new host…"
    if transport == nil {
      attachJoinerTransport()
    } else {
      transport?.ensureBrowsing()
    }
    connectDiscoveredPeersForReconnect()
    scheduleDisconnectGrace(key: "migration") { [weak self] in
      self?.isReconnecting = false
      self?.isMigratingHost = false
      self?.endJoinerSession(reason: .lostConnection)
    }
  }

  private func considerYieldingToSuccessorHost() {
    guard role == .host, let state else { return }
    guard let successor = discoveredPeers.first(where: { shouldYieldHost(to: $0, given: state) }) else {
      return
    }
    demoteAndJoin(successor)
  }

  private func shouldYieldHost(to peer: DiscoveredPeer, given state: GameState) -> Bool {
    guard !state.roomId.isEmpty, peer.roomId == state.roomId else { return false }
    let peerEpoch = peer.epoch ?? 0
    if peerEpoch > state.stateEpoch { return true }
    if peerEpoch < state.stateEpoch { return false }
    guard let peerHost = peer.hostDeviceId, !peerHost.isEmpty else { return false }
    // Equal epoch tie-break — should be rare; lower device id wins.
    return peerHost < state.networkHostDeviceId
      && peerHost != devicePlayerId
  }

  private func demoteAndJoin(_ peer: DiscoveredPeer) {
    isMigratingHost = true
    isReconnecting = true
    cancelPhaseTimer()
    role = .joiner
    statusBanner = "Another phone took over as host…"
    messageTransport?.disconnect()
    transport?.stop()
    transport = nil
    messageTransport = nil
    attachJoinerTransport()
    // Re-fetch peer from discovered list after browse starts; connect when listed.
    // Immediate connect if endpoint map already has it from prior parallel browse.
    transport?.connect(to: peer)
    scheduleDisconnectGrace(key: "migration") { [weak self] in
      self?.isReconnecting = false
      self?.isMigratingHost = false
      self?.endJoinerSession(reason: .lostConnection)
    }
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
      case .drawing, .guessing, .reveal:
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
    if role == .host {
      considerYieldingToSuccessorHost()
    }
    if isReconnecting || isMigratingHost {
      connectDiscoveredPeersForReconnect()
    }
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
      handleHost(message, fromPeerKey: peerKey)
    case .joiner:
      switch message {
      case .syncState(let gameState):
        if let current = state, gameState.stateEpoch < current.stateEpoch {
          // Stale host — ignore.
          return
        }
        applyState(gameState)
        joinStatus = .idle
        let wasReconnecting = isReconnecting || isMigratingHost
        if isReconnecting || isMigratingHost {
          isReconnecting = false
          isMigratingHost = false
          migrationPreviousHostDeviceId = nil
          cancelDisconnectGrace(key: "host")
          cancelDisconnectGrace(key: "migration")
          statusBanner = wasReconnecting ? "Reconnected" : nil
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

  private func handleHost(_ message: NetworkMessage, fromPeerKey peerKey: String) {
    guard var current = state else { return }
    let peerDevice = peerDeviceIds[peerKey] ?? peerKey

    switch message {
    case .hello(let playerId, let name, let avatar):
      // Drop mid-round strangers (lobby-only joins).
      let isReturning = current.players.contains(where: { $0.deviceId == playerId })
      if !isReturning, current.phase != .lobby {
        transport?.disconnectPeer(peerKey)
        return
      }

      bindPeer(peerKey, to: playerId)
      cancelGraceForDevice(playerId)
      reconnectingDeviceIds.remove(playerId)

      if isReturning {
        current = GameEngine.clearAbsent(deviceId: playerId, in: current)
        current = GameEngine.updateName(playerId: playerId, name: name, in: current)
        if !avatar.isEmpty {
          current = GameEngine.updateAvatar(playerId: playerId, avatar: avatar, in: current)
        }
        statusBanner = "\(name) is back"
        sync(current, includeAvatars: true)
        return
      }
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
      // Intentional leave — finalize immediately (no grace).
      cancelDisconnectGrace(key: peerKey)
      if let deviceId = peerDeviceIds[peerKey] {
        reconnectingDeviceIds.remove(deviceId)
      }
      announceDeparture(deviceId: peerDevice, in: current)
      current = GameEngine.handleDisconnect(deviceId: peerDevice, from: current)
      peerDeviceIds[peerKey] = nil
      transport?.disconnectPeer(peerKey)
      sync(current)

    case .syncState, .sessionEnded:
      break
    }
  }

  private func handlePeerChange(peerKey: String, state linkState: PeerLinkState) {
    switch linkState {
    case .connected:
      if role == .joiner {
        joinStatus = .idle
        cancelDisconnectGrace(key: "host")
        send(.hello(playerId: devicePlayerId, name: localDisplayName, avatar: localAvatar))
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
    beginJoinerReconnect()
  }

  private func beginHostPeerGrace(peerKey: String) {
    let peerDevice = peerDeviceIds[peerKey] ?? peerKey
    // Unknown connection that never said hello — drop quietly.
    guard peerDeviceIds[peerKey] != nil || state?.players.contains(where: { $0.deviceId == peerDevice }) == true else {
      peerDeviceIds[peerKey] = nil
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
    let peerDevice = peerDeviceIds[peerKey] ?? peerKey
    reconnectingDeviceIds.remove(peerDevice)
    announceDeparture(deviceId: peerDevice, in: current)
    current = GameEngine.handleDisconnect(deviceId: peerDevice, from: current)
    peerDeviceIds[peerKey] = nil
    sync(current)
  }

  private func bindPeer(_ peerKey: String, to deviceId: String) {
    // Drop stale keys for the same device (reconnect gets a new connection id).
    peerDeviceIds = peerDeviceIds.filter { $0.value != deviceId || $0.key == peerKey }
    peerDeviceIds[peerKey] = deviceId
  }

  private func cancelGraceForDevice(_ deviceId: String) {
    let keys = peerDeviceIds.compactMap { $0.value == deviceId ? $0.key : nil }
    for key in keys {
      cancelDisconnectGrace(key: key)
    }
  }

  private func announceDeparture(deviceId: String, in state: GameState) {
    let names = state.players.filter { $0.deviceId == deviceId }.map(\.name)
    guard let name = names.first else { return }
    if state.phase == .lobby {
      statusBanner = "\(name) left the lobby"
    } else {
      statusBanner = "\(name) left — continuing without them"
    }
  }

  private func scheduleDisconnectGrace(key: String, action: @escaping @MainActor () -> Void) {
    disconnectGraceTasks[key]?.cancel()
    let seconds = disconnectGraceSeconds
    disconnectGraceTasks[key] = Task { [weak self] in
      let ns = UInt64(max(0, seconds) * 1_000_000_000)
      try? await Task.sleep(nanoseconds: ns)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        self?.disconnectGraceTasks[key] = nil
        action()
      }
    }
  }

  private func cancelDisconnectGrace(key: String) {
    disconnectGraceTasks[key]?.cancel()
    disconnectGraceTasks[key] = nil
  }

  private func cancelAllDisconnectGrace() {
    for task in disconnectGraceTasks.values {
      task.cancel()
    }
    disconnectGraceTasks.removeAll()
  }

  private func owns(_ playerId: String, peerDevice: String, in state: GameState) -> Bool {
    state.player(id: playerId)?.deviceId == peerDevice
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
    self.peerDeviceIds = peerDeviceIds
    self.messageTransport = messageTransport
    self.joinStatus = joinStatus
    if let disconnectGraceSeconds {
      self.disconnectGraceSeconds = disconnectGraceSeconds
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
        isReconnecting = false
        isMigratingHost = false
        endJoinerSession(reason: .lostConnection)
      } else {
        attemptHostMigrationAfterHostLoss()
      }
    }
  }

  func testing_attemptHostMigration() {
    attemptHostMigrationAfterHostLoss()
  }

  func testing_promoteToNetworkHost(previousHostDeviceId: String) {
    promoteToNetworkHost(previousHostDeviceId: previousHostDeviceId)
  }

  var testing_isMigratingHost: Bool { isMigratingHost }

  func testing_handleLifecycle(_ phase: AppLifecyclePhase) {
    handleLifecycle(phase)
  }

  var testing_messageTransport: GameMessageTransport? { messageTransport }
}
#endif
