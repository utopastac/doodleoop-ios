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
    XCTAssertEqual(state.revealPadIndex, 0)
    XCTAssertEqual(state.revealStepIndex, 1)
  }

  func testAdvanceRevealStepsThenPadsThenRoundOver() {
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

    // Pad 0: first drawing already visible
    XCTAssertEqual(state.phase, .reveal)
    XCTAssertEqual(state.revealPadIndex, 0)
    XCTAssertEqual(state.revealStepIndex, 1)
    XCTAssertEqual(state.visibleRevealContributions.count, 1)

    // Next → first guess on pad 0
    state = GameEngine.advanceReveal(in: state)
    XCTAssertEqual(state.revealPadIndex, 0)
    XCTAssertEqual(state.revealStepIndex, 2)
    XCTAssertEqual(state.visibleRevealContributions.count, 2)
    XCTAssertFalse(state.isRevealFinished)

    // Next → start pad 1 with first drawing
    state = GameEngine.advanceReveal(in: state)
    XCTAssertEqual(state.phase, .reveal)
    XCTAssertEqual(state.revealPadIndex, 1)
    XCTAssertEqual(state.revealStepIndex, 1)
    XCTAssertEqual(state.visibleRevealContributions.count, 1)

    // Next → last guess on pad 1
    state = GameEngine.advanceReveal(in: state)
    XCTAssertEqual(state.revealPadIndex, 1)
    XCTAssertEqual(state.revealStepIndex, 2)
    XCTAssertTrue(state.isRevealFinished)

    // Finish → round over
    state = GameEngine.advanceReveal(in: state)
    XCTAssertEqual(state.phase, .roundOver)
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
    XCTAssertEqual(state.maxRounds, GameRoundDefaults.maxRounds)
  }

  func testUpdateSettingsClampsAndAppliesInLobby() {
    var state = makeLobby()
    state = GameEngine.updateSettings(
      drawTimeLimitSeconds: 90,
      guessTimeLimitSeconds: 45,
      maxRounds: 6,
      in: state
    )
    XCTAssertEqual(state.drawTimeLimitSeconds, 90)
    XCTAssertEqual(state.guessTimeLimitSeconds, 45)
    XCTAssertEqual(state.maxRounds, 6)

    state = GameEngine.updateSettings(
      drawTimeLimitSeconds: 1,
      guessTimeLimitSeconds: 999,
      maxRounds: 99,
      in: state
    )
    XCTAssertEqual(state.drawTimeLimitSeconds, GameTimerDefaults.minSeconds)
    XCTAssertEqual(state.guessTimeLimitSeconds, GameTimerDefaults.maxSeconds)
    XCTAssertEqual(state.maxRounds, GameRoundDefaults.absoluteMaxRounds)
  }

  func testUpdateSettingsIgnoredDuringRound() {
    var state = makeLobby()
    state = GameEngine.startRound(category: "Animals", in: state)
    let next = GameEngine.updateSettings(
      drawTimeLimitSeconds: 120,
      guessTimeLimitSeconds: 20,
      maxRounds: 4,
      in: state
    )
    XCTAssertEqual(next.drawTimeLimitSeconds, 60)
    XCTAssertEqual(next.guessTimeLimitSeconds, 30)
    XCTAssertEqual(next.maxRounds, GameRoundDefaults.maxRounds)
  }

  func testMaxRoundsCapsBeforePlayerCount() {
    var state = makeLobby(players: 4)
    state = GameEngine.updateSettings(
      drawTimeLimitSeconds: 60,
      guessTimeLimitSeconds: 30,
      maxRounds: 2,
      in: state
    )
    state = GameEngine.startRound(category: "Animals", in: state)
    XCTAssertFalse(state.isRoundComplete)

    state.turnIndex = 2
    XCTAssertTrue(state.isRoundComplete)
  }

  func testMaxRoundsDoesNotExceedPlayerCount() {
    var state = makeLobby(players: 3)
    state = GameEngine.updateSettings(
      drawTimeLimitSeconds: 60,
      guessTimeLimitSeconds: 30,
      maxRounds: 8,
      in: state
    )
    state.turnIndex = 3
    XCTAssertTrue(state.isRoundComplete)
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
      maxRounds: 5,
      in: state
    )
    state = GameEngine.startRound(category: "Sports", in: state)
    state = GameEngine.returnToLobby(in: state)
    XCTAssertEqual(state.phase, .lobby)
    XCTAssertNil(state.phaseEndsAt)
    XCTAssertEqual(state.drawTimeLimitSeconds, 75)
    XCTAssertEqual(state.guessTimeLimitSeconds, 25)
    XCTAssertEqual(state.maxRounds, 5)
  }

  func testRejectsEmptyDrawing() {
    var state = makeLobby(players: 2)
    state = GameEngine.startRound(category: "Animals", in: state)
    let next = GameEngine.submitDrawing(playerId: "p0", drawing: .empty, in: state)
    XCTAssertEqual(next, state)
    XCTAssertTrue(next.submittedPlayerIds.isEmpty)
  }

  func testRejectsEmptyGuess() {
    var state = makeLobby(players: 2)
    state = GameEngine.startRound(category: "Animals", in: state)
    let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.1, y: 0.1)])])
    for i in 0..<2 {
      state = GameEngine.submitDrawing(playerId: "p\(i)", drawing: drawing, in: state)
    }
    let next = GameEngine.submitGuess(playerId: "p0", text: "   ", in: state)
    XCTAssertEqual(next, state)
  }

  func testDuplicateSubmitIgnored() {
    var state = makeLobby(players: 2)
    state = GameEngine.startRound(category: "Animals", in: state)
    let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.1, y: 0.1)])])
    state = GameEngine.submitDrawing(playerId: "p0", drawing: drawing, in: state)
    let again = GameEngine.submitDrawing(playerId: "p0", drawing: drawing, in: state)
    XCTAssertEqual(again.submittedPlayerIds, ["p0"])
    XCTAssertEqual(again.pads, state.pads)
  }

  func testWrongPhaseSubmitNoOps() {
    var state = makeLobby(players: 2)
    let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.1, y: 0.1)])])
    let drawn = GameEngine.submitDrawing(playerId: "p0", drawing: drawing, in: state)
    XCTAssertEqual(drawn, state)

    state = GameEngine.startRound(category: "Animals", in: state)
    let guessed = GameEngine.submitGuess(playerId: "p0", text: "cat", in: state)
    XCTAssertEqual(guessed, state)
  }

  func testStartRoundRequiresTwoPlayersAndCategory() {
    var state = makeLobby(players: 1)
    state = GameEngine.startRound(category: "Animals", in: state)
    XCTAssertEqual(state.phase, .lobby)

    state = makeLobby(players: 2)
    state = GameEngine.startRound(category: "  ", in: state)
    XCTAssertEqual(state.phase, .lobby)
  }

  func testRemovePlayerLobbyAndHostReassignment() {
    var state = makeLobby(players: 3)
    XCTAssertEqual(state.hostId, "p0")
    state = GameEngine.removePlayer(id: "p0", from: state)
    XCTAssertEqual(state.players.map(\.id), ["p1", "p2"])
    XCTAssertEqual(state.hostId, "p1")
  }

  func testRemovePlayerIgnoredMidRound() {
    var state = makeLobby(players: 2)
    state = GameEngine.startRound(category: "Animals", in: state)
    let next = GameEngine.removePlayer(id: "p1", from: state)
    XCTAssertEqual(next.players.count, 2)
  }

  func testExpireTurnInGuessingPhase() {
    var state = makeLobby(players: 2)
    let start = Date(timeIntervalSince1970: 3_000)
    state = GameEngine.startRound(category: "Jobs", in: state, now: start)
    let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.1, y: 0.1)])])
    for i in 0..<2 {
      state = GameEngine.submitDrawing(playerId: "p\(i)", drawing: drawing, in: state, now: start)
    }
    XCTAssertEqual(state.phase, .guessing)

    state = GameEngine.submitGuess(playerId: "p0", text: "cat", in: state, now: start)
    let expired = state.phaseEndsAt!
    state = GameEngine.expireTurn(in: state, now: expired)
    XCTAssertEqual(state.phase, .reveal)
    XCTAssertTrue(state.pads.contains { pad in
      pad.steps.contains {
        if case .guess(let playerId, let text) = $0 {
          return playerId == "p1" && text == "…"
        }
        return false
      }
    })
  }

  func testMultiSeatSameDeviceId() {
    var state = GameState()
    state = GameEngine.addPlayer(id: "p0", name: "A", deviceId: "phone", to: state)
    state = GameEngine.addPlayer(id: "p1", name: "B", deviceId: "phone", to: state)
    XCTAssertEqual(state.players.map(\.deviceId), ["phone", "phone"])
    state = GameEngine.startRound(category: "Food", in: state)
    XCTAssertEqual(state.pads.count, 2)
  }

  func testDisconnectMidRoundFillsAndMarksAbsent() {
    var state = makeLobby(players: 2)
    let now = Date(timeIntervalSince1970: 4_000)
    state = GameEngine.startRound(category: "Jobs", in: state, now: now)
    let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.1, y: 0.1)])])
    state = GameEngine.submitDrawing(playerId: "p0", drawing: drawing, in: state, now: now)

    state = GameEngine.handleDisconnect(deviceId: "d1", from: state, now: now)
    XCTAssertTrue(state.absentDeviceIds.contains("d1"))
    XCTAssertEqual(state.players.count, 2)
    XCTAssertEqual(state.phase, .guessing)
    // Absent seat auto-fills the new guessing turn.
    XCTAssertEqual(state.submittedPlayerIds, ["p1"])
    XCTAssertTrue(state.pads.contains { pad in
      pad.steps.contains {
        if case .drawing(let playerId, let art) = $0 {
          return playerId == "p1" && art.isEmpty
        }
        return false
      }
    })
  }

  func testAbsentDeviceAutoFillsNextTurn() {
    var state = makeLobby(players: 2)
    let now = Date(timeIntervalSince1970: 5_000)
    state = GameEngine.startRound(category: "Jobs", in: state, now: now)
    let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.1, y: 0.1)])])
    state = GameEngine.submitDrawing(playerId: "p0", drawing: drawing, in: state, now: now)
    state = GameEngine.handleDisconnect(deviceId: "d1", from: state, now: now)
    XCTAssertEqual(state.phase, .guessing)

    state = GameEngine.submitGuess(playerId: "p0", text: "cat", in: state, now: now)
    // p1 absent should auto-fill the guess and advance to reveal (2-player round).
    XCTAssertEqual(state.phase, .reveal)
  }

  func testReturnToLobbyDropsAbsentDevices() {
    var state = makeLobby(players: 2)
    let now = Date(timeIntervalSince1970: 6_000)
    state = GameEngine.startRound(category: "Jobs", in: state, now: now)
    state = GameEngine.handleDisconnect(deviceId: "d1", from: state, now: now)
    state.phase = .roundOver
    state = GameEngine.returnToLobby(in: state)
    XCTAssertEqual(state.phase, .lobby)
    XCTAssertEqual(state.players.map(\.id), ["p0"])
    XCTAssertTrue(state.absentDeviceIds.isEmpty)
  }
}
