import Foundation
import MultipeerConnectivity
import Combine

@MainActor
final class GameSession: ObservableObject {
  static let serviceType = "doodleoop-game"

  @Published private(set) var state: GameState?
  @Published private(set) var role: Role = .idle
  @Published private(set) var discoveredPeers: [MCPeerID] = []
  @Published private(set) var handoff: SeatHandoff?

  @Published var localDisplayName: String
  @Published var draftCategory: String = ""

  let devicePlayerId: String
  @Published private(set) var localPlayerId: String

  private var transport: MultipeerTransport?
  private var peerDeviceIds: [String: String] = [:]
  private var cancellables = Set<AnyCancellable>()

  enum Role: Equatable {
    case idle
    case host
    case joiner
  }

  var isHost: Bool { role == .host }

  var localDeviceId: String { devicePlayerId }

  var localSeats: [Player] {
    state?.players.filter { $0.deviceId == devicePlayerId } ?? []
  }

  init() {
    let defaults = UserDefaults.standard
    let name = defaults.string(forKey: "displayName") ?? "Player"
    localDisplayName = name
    if defaults.string(forKey: "displayName") == nil {
      defaults.set(name, forKey: "displayName")
    }

    let id = DeviceIdentity.current()
    devicePlayerId = id
    localPlayerId = id
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
      to: lobby
    )
    state = lobby
    localPlayerId = devicePlayerId

    let transport = MultipeerTransport(displayName: localDisplayName, serviceType: Self.serviceType)
    transport.delegate = self
    transport.startHosting(discoveryInfo: ["host": localDisplayName])
    self.transport = transport
    bindPeers(transport)
  }

  func startBrowsing() {
    leaveGame(clearState: true)
    role = .joiner
    let transport = MultipeerTransport(displayName: localDisplayName, serviceType: Self.serviceType)
    transport.delegate = self
    transport.startBrowsing()
    self.transport = transport
    bindPeers(transport)
  }

  func join(_ peer: MCPeerID) {
    transport?.invite(peer)
  }

  func leaveGame(clearState: Bool = true) {
    if role == .joiner {
      send(.leave)
    }
    transport?.disconnect()
    transport = nil
    cancellables.removeAll()
    discoveredPeers = []
    peerDeviceIds = [:]
    handoff = nil
    role = .idle
    if clearState {
      state = nil
    }
  }

  func updateDisplayName(_ name: String) {
    let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
    guard !trimmed.isEmpty else { return }
    localDisplayName = trimmed
    UserDefaults.standard.set(trimmed, forKey: "displayName")
    guard var current = state else { return }
    if isHost {
      current = GameEngine.updateName(playerId: localPlayerId, name: trimmed, in: current)
      sync(current)
    } else {
      send(.setName(playerId: localPlayerId, name: trimmed))
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

  // MARK: - Internals

  private func bindPeers(_ transport: MultipeerTransport) {
    transport.$discoveredPeers
      .receive(on: DispatchQueue.main)
      .sink { [weak self] peers in
        self?.discoveredPeers = peers
      }
      .store(in: &cancellables)
  }

  private func sync(_ newState: GameState) {
    state = newState
    send(.syncState(newState))
  }

  private func send(_ message: NetworkMessage) {
    transport?.send(message)
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
      if case .syncState(let gameState) = message {
        state = gameState
        prepareLocalHandoffIfNeeded()
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
    case .hello(let playerId, let name):
      peerDeviceIds[peerName] = playerId
      current = GameEngine.addPlayer(
        id: playerId,
        name: name,
        deviceId: playerId,
        to: current
      )
      sync(current)

    case .setName(let playerId, let name):
      guard owns(playerId, peerDevice: peerDevice, in: current) else { return }
      current = GameEngine.updateName(playerId: playerId, name: name, in: current)
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
      current = GameEngine.removePlayers(deviceId: peerDevice, from: current)
      sync(current)

    case .syncState, .startRound, .returnToLobby:
      break
    }
  }

  @MainActor
  private func handlePeerChange(named peerName: String, state sessionState: MCSessionState) {
    switch sessionState {
    case .connected:
      if role == .joiner {
        send(.hello(playerId: devicePlayerId, name: localDisplayName))
      }
    case .notConnected:
      if role == .host, var current = self.state {
        let peerDevice = peerDeviceIds[peerName] ?? peerName
        current = GameEngine.removePlayers(deviceId: peerDevice, from: current)
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
