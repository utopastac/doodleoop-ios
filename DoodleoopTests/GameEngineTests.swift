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

  private func playUntilReveal(_ state: GameState) -> GameState {
    var state = state
    while state.phase == .drawing || state.phase == .guessing || state.phase == .passing {
      if state.phase == .passing {
        state = GameEngine.startNextTurn(in: state)
        continue
      }
      let turn = state.turnIndex
      for i in 0..<state.players.count {
        if turn % 2 == 0 {
          let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.2, y: 0.3)])])
          state = GameEngine.submitDrawing(playerId: "p\(i)", drawing: drawing, in: state)
        } else {
          state = GameEngine.submitGuess(playerId: "p\(i)", text: "guess-\(turn)-\(i)", in: state)
        }
      }
    }
    return state
  }

  private func drawers(on pad: SketchPad) -> [String] {
    pad.steps.compactMap { step in
      if case .drawing(let playerId, _) = step { return playerId }
      return nil
    }
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

    XCTAssertEqual(state.phase, .passing)
    XCTAssertEqual(state.turnIndex, 1)
    state = GameEngine.startNextTurn(in: state)
    XCTAssertEqual(state.phase, .guessing)
    // After one pass left, p0 holds p2's pad (from the right / previous)
    XCTAssertEqual(state.pad(inFrontOf: "p0")?.id, "p2")
    XCTAssertEqual(state.pad(inFrontOf: "p1")?.id, "p0")
    XCTAssertEqual(state.pad(inFrontOf: "p2")?.id, "p1")
  }

  func testStartNextTurnIgnoredOutsidePassing() {
    var state = makeLobby(players: 3)
    state = GameEngine.startRound(category: "Food", in: state)
    let unchanged = GameEngine.startNextTurn(in: state)
    XCTAssertEqual(unchanged, state)
    XCTAssertEqual(unchanged.phase, .drawing)
  }

  /// Regression: turnIndex past seat count used to yield a negative modulo and crash.
  func testPadInFrontOfAfterFullCircle() {
    var state = makeLobby(players: 3)
    state = GameEngine.startRound(category: "Food", in: state)
    state.turnIndex = 3
    XCTAssertEqual(state.pad(inFrontOf: "p0")?.id, "p0")
    XCTAssertEqual(state.pad(inFrontOf: "p1")?.id, "p1")
    XCTAssertEqual(state.pad(inFrontOf: "p2")?.id, "p2")

    state.turnIndex = 4
    XCTAssertEqual(state.pad(inFrontOf: "p0")?.id, "p2")
    XCTAssertEqual(state.pad(inFrontOf: "p1")?.id, "p0")
    XCTAssertEqual(state.pad(inFrontOf: "p2")?.id, "p1")
  }

  func testThreePlayerChainIsDrawGuessDraw() {
    var state = makeLobby(players: 3)
    state = GameEngine.startRound(category: "Jobs", in: state)
    XCTAssertEqual(state.effectiveTurnCount, 3)
    XCTAssertEqual(state.effectiveDrawCount, 2)

    state = playUntilReveal(state)

    XCTAssertEqual(state.phase, .reveal)
    // prompt + draw + guess + draw
    XCTAssertEqual(state.pads[0].steps.count, 4)
    XCTAssertEqual(drawers(on: state.pads[0]), ["p0", "p2"])
  }

  func testFullRoundReachesReveal() {
    var state = makeLobby(players: 3)
    state = GameEngine.startRound(category: "Jobs", in: state)
    state = playUntilReveal(state)

    XCTAssertEqual(state.phase, .reveal)
    XCTAssertEqual(state.pads[0].steps.count, 4)
    XCTAssertEqual(state.revealPadIndex, 0)
    XCTAssertEqual(state.revealStepIndex, 0)
    XCTAssertTrue(state.isRevealPadIntro)
  }

  func testAdvanceRevealStepsThenPadsThenRoundOver() {
    var state = makeLobby(players: 3)
    state = GameEngine.startRound(category: "Jobs", in: state)
    state = playUntilReveal(state)

    // Pad 0 intro — no contributions yet
    XCTAssertEqual(state.phase, .reveal)
    XCTAssertEqual(state.revealPadIndex, 0)
    XCTAssertEqual(state.revealStepIndex, 0)
    XCTAssertTrue(state.isRevealPadIntro)
    XCTAssertEqual(state.visibleRevealContributions.count, 0)

    // Start → first drawing on pad 0
    state = GameEngine.advanceReveal(in: state)
    XCTAssertEqual(state.revealPadIndex, 0)
    XCTAssertEqual(state.revealStepIndex, 1)
    XCTAssertFalse(state.isRevealPadIntro)
    XCTAssertEqual(state.visibleRevealContributions.count, 1)

    // Next → first guess on pad 0
    state = GameEngine.advanceReveal(in: state)
    XCTAssertEqual(state.revealPadIndex, 0)
    XCTAssertEqual(state.revealStepIndex, 2)
    XCTAssertEqual(state.visibleRevealContributions.count, 2)

    // Next → second drawing on pad 0
    state = GameEngine.advanceReveal(in: state)
    XCTAssertEqual(state.revealPadIndex, 0)
    XCTAssertEqual(state.revealStepIndex, 3)
    XCTAssertEqual(state.visibleRevealContributions.count, 3)
    XCTAssertFalse(state.isRevealFinished)

    // Next → pad 1 intro
    state = GameEngine.advanceReveal(in: state)
    XCTAssertEqual(state.phase, .reveal)
    XCTAssertEqual(state.revealPadIndex, 1)
    XCTAssertEqual(state.revealStepIndex, 0)
    XCTAssertTrue(state.isRevealPadIntro)
    XCTAssertEqual(state.visibleRevealContributions.count, 0)

    // Start → first drawing on pad 1
    state = GameEngine.advanceReveal(in: state)
    XCTAssertEqual(state.revealPadIndex, 1)
    XCTAssertEqual(state.revealStepIndex, 1)
    XCTAssertEqual(state.visibleRevealContributions.count, 1)

    // Finish pad 1 contributions (3 per pad: D G D)
    state = GameEngine.advanceReveal(in: state)
    state = GameEngine.advanceReveal(in: state)
    XCTAssertEqual(state.revealPadIndex, 1)
    XCTAssertEqual(state.revealStepIndex, 3)
    XCTAssertFalse(state.isRevealFinished)

    // Next → pad 2 intro, then its contributions
    state = GameEngine.advanceReveal(in: state)
    XCTAssertEqual(state.revealPadIndex, 2)
    XCTAssertEqual(state.revealStepIndex, 0)
    state = GameEngine.advanceReveal(in: state)
    state = GameEngine.advanceReveal(in: state)
    state = GameEngine.advanceReveal(in: state)
    XCTAssertEqual(state.revealPadIndex, 2)
    XCTAssertEqual(state.revealStepIndex, 3)
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

  func testFourPlayerLapIsDrawGuessDrawGuess() {
    var state = makeLobby(players: 4)
    state = GameEngine.startRound(category: "Animals", in: state)
    XCTAssertEqual(state.effectiveDrawCount, 2)
    XCTAssertEqual(state.effectiveTurnCount, 4) // D G D G
    state = playUntilReveal(state)
    XCTAssertEqual(state.pads[0].steps.count, 5) // prompt + 4 contributions
    XCTAssertEqual(drawers(on: state.pads[0]), ["p0", "p2"])
  }

  func testMaxRoundsCapsDrawCountOnLargeTables() {
    var state = makeLobby(players: 10)
    state = GameEngine.updateSettings(
      drawTimeLimitSeconds: 60,
      guessTimeLimitSeconds: 30,
      maxRounds: 2,
      in: state
    )
    state = GameEngine.startRound(category: "Animals", in: state)
    XCTAssertEqual(state.effectiveDrawCount, 2)
    XCTAssertEqual(state.effectiveTurnCount, 4) // D G D G
    XCTAssertFalse(state.isRoundComplete)

    state.turnIndex = 3
    XCTAssertFalse(state.isRoundComplete)
    state.turnIndex = 4
    XCTAssertTrue(state.isRoundComplete)
  }

  func testThreePlayerLapEndsBeforeStarterRedraws() {
    var state = makeLobby(players: 3)
    state = GameEngine.updateSettings(
      drawTimeLimitSeconds: 60,
      guessTimeLimitSeconds: 30,
      maxRounds: 8,
      in: state
    )
    XCTAssertEqual(state.effectiveDrawCount, 2)
    XCTAssertEqual(state.effectiveTurnCount, 3) // D G D
    state.turnIndex = 2
    XCTAssertFalse(state.isRoundComplete)
    state.turnIndex = 3
    XCTAssertTrue(state.isRoundComplete)
  }

  func testStarterNeverDrawsOnOwnPadTwice() {
    for count in 3...6 {
      var state = makeLobby(players: count)
      state = GameEngine.startRound(category: "Animals", in: state)
      state = playUntilReveal(state)
      for pad in state.pads {
        let ids = drawers(on: pad)
        XCTAssertEqual(
          ids.filter { $0 == pad.id }.count,
          1,
          "starter drew twice on pad \(pad.id) with \(count) players"
        )
        XCTAssertEqual(Set(ids).count, ids.count, "someone drew twice on pad \(pad.id)")
      }
    }
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
    var state = makeLobby(players: 3)
    let start = Date(timeIntervalSince1970: 2_000)
    state = GameEngine.startRound(category: "Jobs", in: state, now: start)

    let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.1, y: 0.1)])])
    state = GameEngine.submitDrawing(playerId: "p0", drawing: drawing, in: state, now: start)

    let expired = start.addingTimeInterval(60)
    state = GameEngine.expireTurn(in: state, now: expired)

    XCTAssertEqual(state.phase, .passing)
    XCTAssertEqual(state.turnIndex, 1)
    XCTAssertNil(state.phaseEndsAt)
    state = GameEngine.startNextTurn(in: state, now: expired)
    XCTAssertEqual(state.phase, .guessing)
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
    var state = makeLobby(players: 3)
    state = GameEngine.startRound(category: "Animals", in: state)
    let next = GameEngine.submitDrawing(playerId: "p0", drawing: .empty, in: state)
    XCTAssertEqual(next, state)
    XCTAssertTrue(next.submittedPlayerIds.isEmpty)
  }

  func testRejectsEmptyGuess() {
    var state = makeLobby(players: 3)
    state = GameEngine.startRound(category: "Animals", in: state)
    let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.1, y: 0.1)])])
    for i in 0..<3 {
      state = GameEngine.submitDrawing(playerId: "p\(i)", drawing: drawing, in: state)
    }
    state = GameEngine.startNextTurn(in: state)
    let next = GameEngine.submitGuess(playerId: "p0", text: "   ", in: state)
    XCTAssertEqual(next, state)
  }

  func testCapsPlayerCount() {
    var state = makeLobby(players: GamePartyLimits.maxPlayers)
    let next = GameEngine.addPlayer(
      id: "overflow",
      name: "Too Many",
      deviceId: "overflow",
      to: state
    )
    XCTAssertEqual(next.players.count, GamePartyLimits.maxPlayers)
    XCTAssertEqual(next, state)
  }

  func testCapsGuessLength() {
    var state = makeLobby(players: 3)
    state = GameEngine.startRound(category: "Animals", in: state)
    let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.1, y: 0.1)])])
    for i in 0..<3 {
      state = GameEngine.submitDrawing(playerId: "p\(i)", drawing: drawing, in: state)
    }
    state = GameEngine.startNextTurn(in: state)
    let huge = String(repeating: "a", count: GamePartyLimits.maxGuessLength + 40)
    state = GameEngine.submitGuess(playerId: "p0", text: huge, in: state)
    let text = state.pads.compactMap { pad -> String? in
      if case .guess(let playerId, let guess) = pad.steps.last, playerId == "p0" {
        return guess
      }
      return nil
    }.first
    XCTAssertEqual(text?.count, GamePartyLimits.maxGuessLength)
  }

  func testCapsDrawingInk() {
    var state = makeLobby(players: 3)
    state = GameEngine.startRound(category: "Animals", in: state)
    let points = (0..<(GamePartyLimits.maxPointsPerStroke + 50)).map {
      DrawPoint(x: Double($0) * 0.001, y: 0.5)
    }
    var strokes: [Stroke] = []
    for _ in 0..<(GamePartyLimits.maxStrokesPerDrawing + 10) {
      strokes.append(Stroke(points: points))
    }
    let huge = Drawing(strokes: strokes)
    state = GameEngine.submitDrawing(playerId: "p0", drawing: huge, in: state)
    guard case .drawing(_, let ink) = state.pads[0].steps.last else {
      return XCTFail("expected drawing step")
    }
    XCTAssertEqual(ink.strokes.count, GamePartyLimits.maxStrokesPerDrawing)
    XCTAssertEqual(ink.strokes.first?.points.count, GamePartyLimits.maxPointsPerStroke)
  }

  func testDuplicateSubmitIgnored() {
    var state = makeLobby(players: 3)
    state = GameEngine.startRound(category: "Animals", in: state)
    let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.1, y: 0.1)])])
    state = GameEngine.submitDrawing(playerId: "p0", drawing: drawing, in: state)
    let again = GameEngine.submitDrawing(playerId: "p0", drawing: drawing, in: state)
    XCTAssertEqual(again.submittedPlayerIds, ["p0"])
    XCTAssertEqual(again.pads, state.pads)
  }

  func testWrongPhaseSubmitNoOps() {
    var state = makeLobby(players: 3)
    let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.1, y: 0.1)])])
    let drawn = GameEngine.submitDrawing(playerId: "p0", drawing: drawing, in: state)
    XCTAssertEqual(drawn, state)

    state = GameEngine.startRound(category: "Animals", in: state)
    let guessed = GameEngine.submitGuess(playerId: "p0", text: "cat", in: state)
    XCTAssertEqual(guessed, state)
  }

  func testStartRoundRequiresThreePlayersAndCategory() {
    var state = makeLobby(players: 1)
    state = GameEngine.startRound(category: "Animals", in: state)
    XCTAssertEqual(state.phase, .lobby)

    state = makeLobby(players: 2)
    state = GameEngine.startRound(category: "Animals", in: state)
    XCTAssertEqual(state.phase, .lobby)

    state = makeLobby(players: 3)
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
    var state = makeLobby(players: 3)
    state = GameEngine.startRound(category: "Animals", in: state)
    let next = GameEngine.removePlayer(id: "p1", from: state)
    XCTAssertEqual(next.players.count, 3)
  }

  func testExpireTurnInGuessingPhase() {
    var state = makeLobby(players: 3)
    let start = Date(timeIntervalSince1970: 3_000)
    state = GameEngine.startRound(category: "Jobs", in: state, now: start)
    let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.1, y: 0.1)])])
    for i in 0..<3 {
      state = GameEngine.submitDrawing(playerId: "p\(i)", drawing: drawing, in: state, now: start)
    }
    state = GameEngine.startNextTurn(in: state, now: start)
    XCTAssertEqual(state.phase, .guessing)

    state = GameEngine.submitGuess(playerId: "p0", text: "cat", in: state, now: start)
    let expired = state.phaseEndsAt!
    state = GameEngine.expireTurn(in: state, now: expired)
    // 3-player game still has a final draw turn after the first guess.
    XCTAssertEqual(state.phase, .passing)
    XCTAssertEqual(state.turnIndex, 2)
    state = GameEngine.startNextTurn(in: state, now: expired)
    XCTAssertEqual(state.phase, .drawing)
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
    state = GameEngine.addPlayer(id: "p2", name: "C", deviceId: "phone", to: state)
    XCTAssertEqual(state.players.map(\.deviceId), ["phone", "phone", "phone"])
    state = GameEngine.startRound(category: "Food", in: state)
    XCTAssertEqual(state.pads.count, 3)
  }

  func testDisconnectMidRoundFillsAndMarksAbsent() {
    var state = makeLobby(players: 3)
    let now = Date(timeIntervalSince1970: 4_000)
    state = GameEngine.startRound(category: "Jobs", in: state, now: now)
    let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.1, y: 0.1)])])
    state = GameEngine.submitDrawing(playerId: "p0", drawing: drawing, in: state, now: now)
    state = GameEngine.submitDrawing(playerId: "p2", drawing: drawing, in: state, now: now)

    state = GameEngine.handleDisconnect(deviceId: "d1", from: state, now: now)
    XCTAssertTrue(state.absentDeviceIds.contains("d1"))
    XCTAssertEqual(state.players.count, 3)
    XCTAssertEqual(state.phase, .passing)
    XCTAssertTrue(state.submittedPlayerIds.isEmpty)
    XCTAssertTrue(state.pads.contains { pad in
      pad.steps.contains {
        if case .drawing(let playerId, let art) = $0 {
          return playerId == "p1" && art.isEmpty
        }
        return false
      }
    })

    state = GameEngine.startNextTurn(in: state, now: now)
    XCTAssertEqual(state.phase, .guessing)
    // Absent seat auto-fills the new guessing turn.
    XCTAssertEqual(state.submittedPlayerIds, ["p1"])
  }

  func testAbsentDeviceAutoFillsNextTurn() {
    var state = makeLobby(players: 3)
    let now = Date(timeIntervalSince1970: 5_000)
    state = GameEngine.startRound(category: "Jobs", in: state, now: now)
    let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.1, y: 0.1)])])
    state = GameEngine.submitDrawing(playerId: "p0", drawing: drawing, in: state, now: now)
    state = GameEngine.submitDrawing(playerId: "p2", drawing: drawing, in: state, now: now)
    state = GameEngine.handleDisconnect(deviceId: "d1", from: state, now: now)
    XCTAssertEqual(state.phase, .passing)
    state = GameEngine.startNextTurn(in: state, now: now)
    XCTAssertEqual(state.phase, .guessing)

    state = GameEngine.submitGuess(playerId: "p0", text: "cat", in: state, now: now)
    state = GameEngine.submitGuess(playerId: "p2", text: "dog", in: state, now: now)
    // p1 absent auto-fills the guess; host then starts the final draw turn.
    XCTAssertEqual(state.phase, .passing)
    XCTAssertEqual(state.turnIndex, 2)
    state = GameEngine.startNextTurn(in: state, now: now)
    XCTAssertEqual(state.phase, .drawing)
  }

  func testReturnToLobbyDropsAbsentDevices() {
    var state = makeLobby(players: 3)
    let now = Date(timeIntervalSince1970: 6_000)
    state = GameEngine.startRound(category: "Jobs", in: state, now: now)
    state = GameEngine.handleDisconnect(deviceId: "d1", from: state, now: now)
    state.phase = .roundOver
    state = GameEngine.returnToLobby(in: state)
    XCTAssertEqual(state.phase, .lobby)
    XCTAssertEqual(state.players.map(\.id), ["p0", "p2"])
    XCTAssertTrue(state.absentDeviceIds.isEmpty)
  }

  func testElectsLowestPresentDeviceId() {
    var state = GameState()
    state = GameEngine.addPlayer(id: "p0", name: "A", deviceId: "zebra", to: state)
    state = GameEngine.addPlayer(id: "p1", name: "B", deviceId: "alpha", to: state)
    state = GameEngine.addPlayer(id: "p2", name: "C", deviceId: "middle", to: state)
    XCTAssertEqual(GameEngine.electedNetworkHostDeviceId(in: state), "alpha")

    state = GameEngine.handleDisconnect(deviceId: "alpha", from: state)
    // Lobby disconnect removes alpha's seats.
    XCTAssertEqual(GameEngine.electedNetworkHostDeviceId(in: state), "middle")
  }

  func testClaimNetworkHostBumpsEpoch() {
    var state = GameState()
    state.networkHostDeviceId = "old"
    state.stateEpoch = 2
    state = GameEngine.claimNetworkHost(deviceId: "new", in: state)
    XCTAssertEqual(state.networkHostDeviceId, "new")
    XCTAssertEqual(state.stateEpoch, 3)
  }
}
