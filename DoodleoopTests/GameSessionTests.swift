import XCTest
@testable import Doodleoop

@MainActor
final class GameSessionTests: XCTestCase {
  private func makeHistoryStore() throws -> GameHistoryStore {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("doodleoop-session-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return GameHistoryStore(directory: dir)
  }

  private func lobbyState(hostId: String = "host", joinerId: String = "joiner") -> GameState {
    var state = GameState()
    state = GameEngine.addPlayer(id: hostId, name: "Host", deviceId: hostId, to: state)
    state = GameEngine.addPlayer(id: joinerId, name: "Joiner", deviceId: joinerId, to: state)
    return state
  }

  func testJoinerAppliesSyncState() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    let avatar = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.2, y: 0.3)])])
    var incoming = lobbyState()
    incoming.players[0].avatar = avatar

    session.testing_configure(role: .joiner, state: nil)
    session.testing_handle(.syncState(incoming), fromPeerKey: "Host")

    XCTAssertEqual(session.state?.players.count, 2)
    XCTAssertEqual(session.state?.player(id: "host")?.avatar, avatar)
  }

  func testJoinerRestoresAvatarsWhenSyncStripsThem() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    let avatar = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.4, y: 0.5)])])
    var lobby = lobbyState()
    lobby.players[0].avatar = avatar

    session.testing_configure(role: .joiner, state: nil)
    session.testing_handle(.syncState(lobby), fromPeerKey: "Host")

    var drawing = lobby
    drawing = GameEngine.startRound(category: "Food", in: drawing)
    let stripped = drawing.strippingAvatars()
    session.testing_handle(.syncState(stripped), fromPeerKey: "Host")

    XCTAssertEqual(session.state?.phase, .drawing)
    XCTAssertEqual(session.state?.player(id: "host")?.avatar, avatar)
  }

  func testJoinerSessionEndedLeavesGame() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    session.testing_configure(role: .joiner, state: lobbyState())
    session.testing_handle(.sessionEnded, fromPeerKey: "Host")
    XCTAssertEqual(session.role, .idle)
    XCTAssertNil(session.state)
    XCTAssertEqual(session.alert, .hostEndedGame)
  }

  func testJoinerHostDisconnectLeavesGame() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    var state = lobbyState()
    state.roomId = "room-1"
    state.networkHostDeviceId = "host"
    state.stateEpoch = 1
    session.testing_configure(role: .joiner, state: state)
    session.testing_peerChange(peerKey: "Host", state: .notConnected)
    XCTAssertEqual(session.role, .joiner)
    XCTAssertNotNil(session.state)
    XCTAssertTrue(session.isReconnecting)

    // Reconnect grace → migrate seek (we're not the elected host among host/joiner ids).
    session.testing_expireDisconnectGrace(for: "host")
    XCTAssertTrue(session.testing_isMigratingHost)
    XCTAssertEqual(session.role, .joiner)

    session.testing_expireDisconnectGrace(for: "migration")
    XCTAssertEqual(session.role, .idle)
    XCTAssertNil(session.state)
    XCTAssertEqual(session.alert, .lostConnection)
  }

  func testJoinerPromotesWhenElectedAfterHostLoss() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    let me = session.devicePlayerId
    var state = GameState()
    state.roomId = "room-migrate"
    state.networkHostDeviceId = "old-host"
    state.stateEpoch = 3
    state = GameEngine.addPlayer(id: "old-host", name: "Host", deviceId: "old-host", to: state)
    state = GameEngine.addPlayer(id: me, name: "Me", deviceId: me, to: state)
    state = GameEngine.startRound(category: "Food", in: state)

    let recorder = RecordingMessageTransport()
    session.testing_configure(
      role: .joiner,
      state: state,
      messageTransport: recorder
    )
    session.testing_attemptHostMigration()

    XCTAssertEqual(session.role, .host)
    XCTAssertEqual(session.state?.networkHostDeviceId, me)
    XCTAssertEqual(session.state?.stateEpoch, 4)
    XCTAssertTrue(session.state?.absentDeviceIds.contains("old-host") ?? false)
    XCTAssertFalse(session.testing_isMigratingHost)
    XCTAssertTrue(recorder.sent.contains { if case .syncState = $0 { return true }; return false })
  }

  func testJoinerIgnoresStaleSyncEpoch() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    var current = lobbyState()
    current.roomId = "r"
    current.networkHostDeviceId = "host"
    current.stateEpoch = 5
    session.testing_configure(role: .joiner, state: current)

    var stale = current
    stale.stateEpoch = 4
    stale.category = "should-not-apply"
    session.testing_handle(.syncState(stale), fromPeerKey: "Host")
    XCTAssertEqual(session.state?.stateEpoch, 5)
    XCTAssertEqual(session.state?.category, "")
  }

  func testJoinerInviteTimeoutStaysBrowsing() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    session.testing_configure(
      role: .joiner,
      state: nil,
      joinStatus: .connecting(to: "HostPhone")
    )
    session.testing_peerChange(peerKey: "HostPhone", state: .notConnected)
    XCTAssertEqual(session.role, .joiner)
    XCTAssertNil(session.state)
    guard case .failed(let message) = session.joinStatus else {
      return XCTFail("Expected join failure, got \(session.joinStatus)")
    }
    XCTAssertTrue(message.contains("HostPhone"))
  }

  func testHostDisconnectWaitsBeforeRemovingJoiner() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    let recorder = RecordingMessageTransport()
    session.testing_configure(
      role: .host,
      state: lobbyState(),
      peerDeviceIds: ["JoinerPhone": "joiner"],
      messageTransport: recorder
    )
    session.testing_peerChange(peerKey: "JoinerPhone", state: .notConnected)
    XCTAssertEqual(session.state?.players.map(\.id), ["host", "joiner"])
    XCTAssertEqual(session.statusBanner, "Waiting for Joiner to reconnect…")
    XCTAssertTrue(session.reconnectingDeviceIds.contains("joiner"))

    session.testing_expireDisconnectGrace(for: "JoinerPhone")
    XCTAssertEqual(session.state?.players.map(\.id), ["host"])
    XCTAssertEqual(session.statusBanner, "Joiner left the lobby")
    XCTAssertFalse(session.reconnectingDeviceIds.contains("joiner"))
  }

  func testHostRejoinClearsAbsentDevice() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    let recorder = RecordingMessageTransport()
    var state = lobbyState()
    state = GameEngine.startRound(category: "Food", in: state)
    state = GameEngine.handleDisconnect(deviceId: "joiner", from: state)
    XCTAssertTrue(state.absentDeviceIds.contains("joiner"))

    session.testing_configure(
      role: .host,
      state: state,
      messageTransport: recorder
    )
    session.testing_handle(
      .hello(playerId: "joiner", name: "Joiner", avatar: .empty),
      fromPeerKey: "JoinerPhone"
    )
    XCTAssertFalse(session.state?.absentDeviceIds.contains("joiner") ?? true)
    XCTAssertEqual(session.statusBanner, "Joiner is back")
  }

  func testHostRejectsMidRoundStranger() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    let recorder = RecordingMessageTransport()
    var state = lobbyState()
    state = GameEngine.startRound(category: "Food", in: state)
    session.testing_configure(
      role: .host,
      state: state,
      messageTransport: recorder
    )
    session.testing_handle(
      .hello(playerId: "stranger", name: "Stranger", avatar: .empty),
      fromPeerKey: "StrangerPhone"
    )
    XCTAssertEqual(session.state?.players.map(\.id), ["host", "joiner"])
    XCTAssertTrue(recorder.sent.isEmpty)
  }

  func testBackgroundTipOnReturn() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    session.testing_configure(role: .host, state: lobbyState())
    session.testing_handleLifecycle(.background)
    session.testing_handleLifecycle(.active)
    XCTAssertTrue(session.showStayInAppTip)
  }

  func testHostDisconnectShowsDepartureBanner() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    let recorder = RecordingMessageTransport()
    session.testing_configure(
      role: .host,
      state: lobbyState(),
      peerDeviceIds: ["JoinerPhone": "joiner"],
      messageTransport: recorder
    )
    session.testing_peerChange(peerKey: "JoinerPhone", state: .notConnected)
    session.testing_expireDisconnectGrace(for: "JoinerPhone")
    XCTAssertEqual(session.statusBanner, "Joiner left the lobby")
  }

  func testHostLeaveBroadcastsSessionEnded() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    let recorder = RecordingMessageTransport()
    session.testing_configure(
      role: .host,
      state: lobbyState(),
      messageTransport: recorder
    )
    session.leaveGame()
    XCTAssertEqual(recorder.sent, [.sessionEnded])
    XCTAssertTrue(recorder.didDisconnect)
    XCTAssertEqual(session.role, .idle)
  }

  func testHostDisconnectInLobbyRemovesJoiner() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    let recorder = RecordingMessageTransport()
    session.testing_configure(
      role: .host,
      state: lobbyState(),
      peerDeviceIds: ["JoinerPhone": "joiner"],
      messageTransport: recorder
    )
    session.testing_peerChange(peerKey: "JoinerPhone", state: .notConnected)
    session.testing_expireDisconnectGrace(for: "JoinerPhone")
    XCTAssertEqual(session.state?.players.map(\.id), ["host"])
    XCTAssertTrue(recorder.sent.contains { if case .syncState = $0 { return true }; return false })
  }

  func testHostIgnoresSubmitFromWrongDevice() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    let recorder = RecordingMessageTransport()
    var state = lobbyState()
    state = GameEngine.startRound(category: "Food", in: state)
    session.testing_configure(
      role: .host,
      state: state,
      peerDeviceIds: ["JoinerPhone": "joiner"],
      messageTransport: recorder
    )
    let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.1, y: 0.1)])])
    session.testing_handle(
      .submitDrawing(playerId: "host", drawing: drawing),
      fromPeerKey: "JoinerPhone"
    )
    XCTAssertTrue(session.state?.submittedPlayerIds.isEmpty ?? false)
    XCTAssertTrue(recorder.sent.isEmpty)
  }

  func testMessageFramingRoundTrip() throws {
    var decoder = MessageFraming.Decoder()
    let payload = Data("{\"hello\":true}".utf8)
    let framed = MessageFraming.encode(payload)
    // Split across chunks to exercise the buffer.
    let mid = framed.count / 2
    let first = try decoder.append(framed.prefix(mid))
    XCTAssertTrue(first.isEmpty)
    let second = try decoder.append(framed.suffix(from: mid))
    XCTAssertEqual(second, [payload])
  }

  func testNetworkMessageCodableRoundTrip() throws {
    var state = lobbyState()
    state.revealStepIndex = 2
    state.drawTimeLimitSeconds = 45
    let messages: [NetworkMessage] = [
      .syncState(state),
      .hello(playerId: "p", name: "Pat", avatar: .empty),
      .sessionEnded,
      .leave,
      .advanceReveal,
    ]
    for message in messages {
      let data = try JSONEncoder().encode(message)
      let decoded = try JSONDecoder().decode(NetworkMessage.self, from: data)
      XCTAssertEqual(decoded, message)
    }
  }

  func testGameStateDecodesMissingAbsentDeviceIds() throws {
    let json = """
    {
      "phase": "lobby",
      "players": [],
      "hostId": "",
      "category": "",
      "pads": [],
      "turnIndex": 0,
      "submittedPlayerIds": [],
      "revealPadIndex": 0
    }
    """.data(using: .utf8)!
    let state = try JSONDecoder().decode(GameState.self, from: json)
    XCTAssertTrue(state.absentDeviceIds.isEmpty)
    XCTAssertEqual(state.revealStepIndex, 0)
    XCTAssertEqual(state.drawTimeLimitSeconds, GameTimerDefaults.drawSeconds)
  }

  func testConnectionPresencesTrackReconnect() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    session.testing_configure(
      role: .host,
      state: lobbyState(),
      peerDeviceIds: ["JoinerPhone": "joiner"]
    )
    session.testing_peerChange(peerKey: "JoinerPhone", state: .notConnected)
    let joiner = session.connectionPresences.first { $0.deviceId == "joiner" }
    XCTAssertEqual(joiner?.status, .reconnecting)
    XCTAssertTrue(session.showsConnectionStrip)
  }
}
