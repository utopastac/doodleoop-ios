import XCTest
@testable import Doodleoop

final class GameEngineTests: XCTestCase {
  func makeLobby(players: Int = 3) -> GameState {
    var state = GameState()
    for i in 0..<players {
      state = GameEngine.addPlayer(
        id: "p\(i)",
        name: "P\(i)",
        deviceId: "d\(i)",
        to: state
      )
    }
    return state
  }

  func testStartRoundCreatesPadsAndDrawingPhase() {
    var state = makeLobby()
    state = GameEngine.startRound(category: "Animals", in: state)
    XCTAssertEqual(state.phase, .drawing)
    XCTAssertEqual(state.pads.count, 3)
    XCTAssertEqual(state.category, "Animals")
    XCTAssertTrue(state.isDrawTurn)
  }

  func testPadPassesLeftEachTurn() {
    var state = makeLobby()
    state = GameEngine.startRound(category: "Food", in: state)

    // Turn 0: each draws on their own pad
    XCTAssertEqual(state.pad(inFrontOf: "p0")?.id, "p0")
    XCTAssertEqual(state.pad(inFrontOf: "p1")?.id, "p1")

    for i in 0..<3 {
      let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.1, y: 0.1)])])
      state = GameEngine.submitDrawing(playerId: "p\(i)", drawing: drawing, in: state)
    }

    XCTAssertEqual(state.phase, .guessing)
    XCTAssertEqual(state.turnIndex, 1)
    // After one pass left, p0 holds p2's pad (from the right / previous)
    XCTAssertEqual(state.pad(inFrontOf: "p0")?.id, "p2")
    XCTAssertEqual(state.pad(inFrontOf: "p1")?.id, "p0")
    XCTAssertEqual(state.pad(inFrontOf: "p2")?.id, "p1")
  }

  func testFullRoundReachesReveal() {
    var state = makeLobby(players: 2)
    state = GameEngine.startRound(category: "Jobs", in: state)

    for turn in 0..<2 {
      for i in 0..<2 {
        if turn % 2 == 0 {
          let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.2, y: 0.3)])])
          state = GameEngine.submitDrawing(playerId: "p\(i)", drawing: drawing, in: state)
        } else {
          state = GameEngine.submitGuess(playerId: "p\(i)", text: "guess-\(turn)-\(i)", in: state)
        }
      }
    }

    XCTAssertEqual(state.phase, .reveal)
    XCTAssertEqual(state.pads[0].steps.count, 3) // prompt + 2 contributions
  }

  func testAddPlayerStoresAvatar() {
    let avatar = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.5, y: 0.5)])])
    var state = GameState()
    state = GameEngine.addPlayer(
      id: "p0",
      name: "Ada",
      deviceId: "d0",
      avatar: avatar,
      to: state
    )
    XCTAssertEqual(state.players.first?.avatar, avatar)
  }

  func testUpdateAvatar() {
    var state = makeLobby(players: 1)
    let avatar = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.2, y: 0.8)])])
    state = GameEngine.updateAvatar(playerId: "p0", avatar: avatar, in: state)
    XCTAssertEqual(state.player(id: "p0")?.avatar, avatar)
  }

  func testDefaultTimerSettings() {
    let state = GameState()
    XCTAssertEqual(state.drawTimeLimitSeconds, 60)
    XCTAssertEqual(state.guessTimeLimitSeconds, 30)
  }

  func testUpdateSettingsClampsAndAppliesInLobby() {
    var state = makeLobby()
    state = GameEngine.updateSettings(
      drawTimeLimitSeconds: 90,
      guessTimeLimitSeconds: 45,
      in: state
    )
    XCTAssertEqual(state.drawTimeLimitSeconds, 90)
    XCTAssertEqual(state.guessTimeLimitSeconds, 45)

    state = GameEngine.updateSettings(
      drawTimeLimitSeconds: 1,
      guessTimeLimitSeconds: 999,
      in: state
    )
    XCTAssertEqual(state.drawTimeLimitSeconds, GameTimerDefaults.minSeconds)
    XCTAssertEqual(state.guessTimeLimitSeconds, GameTimerDefaults.maxSeconds)
  }

  func testUpdateSettingsIgnoredDuringRound() {
    var state = makeLobby()
    state = GameEngine.startRound(category: "Animals", in: state)
    let next = GameEngine.updateSettings(
      drawTimeLimitSeconds: 120,
      guessTimeLimitSeconds: 20,
      in: state
    )
    XCTAssertEqual(next.drawTimeLimitSeconds, 60)
    XCTAssertEqual(next.guessTimeLimitSeconds, 30)
  }

  func testStartRoundSetsDrawingDeadline() {
    var state = makeLobby()
    state = GameEngine.updateSettings(
      drawTimeLimitSeconds: 45,
      guessTimeLimitSeconds: 20,
      in: state
    )
    let now = Date(timeIntervalSince1970: 1_000)
    state = GameEngine.startRound(category: "Food", in: state, now: now)
    XCTAssertEqual(state.phaseEndsAt, now.addingTimeInterval(45))
  }

  func testExpireTurnFillsMissingAndAdvances() {
    var state = makeLobby(players: 2)
    let start = Date(timeIntervalSince1970: 2_000)
    state = GameEngine.startRound(category: "Jobs", in: state, now: start)

    let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.1, y: 0.1)])])
    state = GameEngine.submitDrawing(playerId: "p0", drawing: drawing, in: state, now: start)

    let expired = start.addingTimeInterval(60)
    state = GameEngine.expireTurn(in: state, now: expired)

    XCTAssertEqual(state.phase, .guessing)
    XCTAssertEqual(state.turnIndex, 1)
    XCTAssertEqual(state.phaseEndsAt, expired.addingTimeInterval(30))
    XCTAssertTrue(state.pads.contains { pad in
      pad.steps.contains {
        if case .drawing(let playerId, let art) = $0 {
          return playerId == "p1" && art.isEmpty
        }
        return false
      }
    })
  }

  func testSettingsSurviveReturnToLobby() {
    var state = makeLobby()
    state = GameEngine.updateSettings(
      drawTimeLimitSeconds: 75,
      guessTimeLimitSeconds: 25,
      in: state
    )
    state = GameEngine.startRound(category: "Sports", in: state)
    state = GameEngine.returnToLobby(in: state)
    XCTAssertEqual(state.phase, .lobby)
    XCTAssertNil(state.phaseEndsAt)
    XCTAssertEqual(state.drawTimeLimitSeconds, 75)
    XCTAssertEqual(state.guessTimeLimitSeconds, 25)
  }
}
