import XCTest
@testable import Doodleoop

final class SavedGameTests: XCTestCase {
  func testInitFromStateRequiresRoundOverWithPads() {
    var state = makeRoundOverState()
    XCTAssertNotNil(SavedGame(from: state))

    state.phase = .reveal
    XCTAssertNil(SavedGame(from: state))

    state.phase = .roundOver
    state.pads = []
    XCTAssertNil(SavedGame(from: state))
  }

  func testContentKeyStableForSameRound() {
    let state = makeRoundOverState()
    let a = SavedGame.makeContentKey(category: state.category, players: state.players, pads: state.pads)
    let b = SavedGame.makeContentKey(category: state.category, players: state.players, pads: state.pads)
    XCTAssertEqual(a, b)
    XCTAssertEqual(a.count, 64) // sha256 hex
  }

  func testContentKeyChangesWhenPadContentChanges() {
    var state = makeRoundOverState()
    let original = SavedGame.makeContentKey(
      category: state.category,
      players: state.players,
      pads: state.pads
    )
    state.pads[0].steps.append(.guess(playerId: "p0", text: "extra"))
    let altered = SavedGame.makeContentKey(
      category: state.category,
      players: state.players,
      pads: state.pads
    )
    XCTAssertNotEqual(original, altered)
  }

  func testPlayerLookupNamesAndPreviewDrawing() throws {
    let state = makeRoundOverState()
    let game = try XCTUnwrap(SavedGame(from: state))
    XCTAssertEqual(game.player(id: "p0")?.name, "Ada")
    XCTAssertNil(game.player(id: "missing"))
    XCTAssertEqual(game.playerNamesSummary, "Ada, Bea, Cyd")
    XCTAssertNotNil(game.previewDrawing)
    XCTAssertFalse(game.previewDrawing?.isEmpty ?? true)
  }

  func testHistoryTimestampFormat() {
    let date = Date(timeIntervalSince1970: 1_775_577_600) // 2026-04-07 12:00 UTC-ish; formatters use locale
    let game = SavedGame(
      completedAt: date,
      category: "Animals",
      players: [Player(id: "p0", deviceId: "d0", name: "Ada", avatar: .empty)],
      pads: [SketchPad(id: "p0", steps: [.prompt("Animals")])],
      contentKey: "abc"
    )
    let stamp = game.historyTimestamp
    XCTAssertTrue(stamp.contains(" // "))
    XCTAssertTrue(stamp.contains("am") || stamp.contains("pm"))
  }

  func testSavedGameCodableRoundTrip() throws {
    let state = makeRoundOverState()
    let game = try XCTUnwrap(SavedGame(from: state, completedAt: Date(timeIntervalSince1970: 100)))
    let data = try JSONEncoder().encode(game)
    let decoded = try JSONDecoder().decode(SavedGame.self, from: data)
    XCTAssertEqual(decoded, game)
  }

  private func makeRoundOverState() -> GameState {
    var state = GameState()
    state = GameEngine.addPlayer(id: "p0", name: "Ada", deviceId: "d0", to: state)
    state = GameEngine.addPlayer(id: "p1", name: "Bea", deviceId: "d1", to: state)
    state = GameEngine.addPlayer(id: "p2", name: "Cyd", deviceId: "d2", to: state)
    state = GameEngine.startRound(category: "Animals", in: state)

    while state.phase == .drawing || state.phase == .guessing || state.phase == .passing {
      if state.phase == .passing {
        state = GameEngine.startNextTurn(in: state)
        continue
      }
      let turn = state.turnIndex
      for i in 0..<3 {
        if turn % 2 == 0 {
          let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.2, y: 0.3)])])
          state = GameEngine.submitDrawing(playerId: "p\(i)", drawing: drawing, in: state)
        } else {
          state = GameEngine.submitGuess(playerId: "p\(i)", text: "cat-\(i)", in: state)
        }
      }
    }

    while state.phase == .reveal {
      state = GameEngine.advanceReveal(in: state)
    }
    return state
  }
}
