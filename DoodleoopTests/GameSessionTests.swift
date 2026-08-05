import XCTest
import MultipeerConnectivity
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
    session.testing_handle(.syncState(incoming), fromPeerNamed: "Host")

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
    session.testing_handle(.syncState(lobby), fromPeerNamed: "Host")

    var drawing = lobby
    drawing = GameEngine.startRound(category: "Food", in: drawing)
    let stripped = drawing.strippingAvatars()
    session.testing_handle(.syncState(stripped), fromPeerNamed: "Host")

    XCTAssertEqual(session.state?.phase, .drawing)
    XCTAssertEqual(session.state?.player(id: "host")?.avatar, avatar)
  }

  func testJoinerSessionEndedLeavesGame() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    session.testing_configure(role: .joiner, state: lobbyState())
    session.testing_handle(.sessionEnded, fromPeerNamed: "Host")
    XCTAssertEqual(session.role, .idle)
    XCTAssertNil(session.state)
    XCTAssertEqual(session.alert, .hostEndedGame)
  }

  func testJoinerHostDisconnectLeavesGame() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    session.testing_configure(role: .joiner, state: lobbyState())
    session.testing_peerChange(named: "Host", state: .notConnected)
    XCTAssertEqual(session.role, .idle)
    XCTAssertNil(session.state)
    XCTAssertEqual(session.alert, .lostConnection)
  }

  func testJoinerInviteTimeoutStaysBrowsing() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store)
    session.testing_configure(
      role: .joiner,
      state: nil,
      joinStatus: .connecting(to: "HostPhone")
    )
    session.testing_peerChange(named: "HostPhone", state: .notConnected)
    XCTAssertEqual(session.role, .joiner)
    XCTAssertNil(session.state)
    guard case .failed(let message) = session.joinStatus else {
      return XCTFail("Expected join failure, got \(session.joinStatus)")
    }
    XCTAssertTrue(message.contains("HostPhone"))
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
    session.testing_peerChange(named: "JoinerPhone", state: .notConnected)
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
    session.testing_peerChange(named: "JoinerPhone", state: .notConnected)
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
      fromPeerNamed: "JoinerPhone"
    )
    XCTAssertTrue(session.state?.submittedPlayerIds.isEmpty ?? false)
    XCTAssertTrue(recorder.sent.isEmpty)
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
}
