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
}
