import XCTest
@testable import Doodleoop

@MainActor
final class GameHistoryStoreTests: XCTestCase {
  private var directory: URL!
  private var store: GameHistoryStore!

  override func setUp() async throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("DoodleoopHistoryTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    store = GameHistoryStore(directory: directory)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: directory)
    store = nil
    directory = nil
  }

  func testSaveRoundOverOnce() {
    var state = makeRoundOverState()
    XCTAssertNotNil(store.saveIfNeeded(from: state))
    XCTAssertEqual(store.games.count, 1)

    XCTAssertNil(store.saveIfNeeded(from: state), "Same round should not save twice")
    XCTAssertEqual(store.games.count, 1)

    state.category = "Different category"
    // Category change alone still shares pad content — remake key via new SavedGame
    var altered = state
    altered.pads[0].steps.append(.guess(playerId: "p0", text: "extra"))
    XCTAssertNotNil(store.saveIfNeeded(from: altered))
    XCTAssertEqual(store.games.count, 2)
  }

  func testIgnoresNonRoundOver() {
    var state = makeRoundOverState()
    state.phase = .reveal
    XCTAssertNil(store.saveIfNeeded(from: state))
    XCTAssertTrue(store.games.isEmpty)
  }

  func testPersistsAcrossReload() {
    let state = makeRoundOverState()
    let saved = store.saveIfNeeded(from: state)
    XCTAssertNotNil(saved)

    let reloaded = GameHistoryStore(directory: directory)
    XCTAssertEqual(reloaded.games.count, 1)
    XCTAssertEqual(reloaded.games.first?.category, "Animals")
    XCTAssertEqual(reloaded.games.first?.pads.count, 2)
  }

  func testDeleteRemovesFile() {
    let state = makeRoundOverState()
    guard let saved = store.saveIfNeeded(from: state) else {
      return XCTFail("expected save")
    }
    store.delete(saved)
    XCTAssertTrue(store.games.isEmpty)

    let reloaded = GameHistoryStore(directory: directory)
    XCTAssertTrue(reloaded.games.isEmpty)
  }

  private func makeRoundOverState() -> GameState {
    var state = GameState()
    state = GameEngine.addPlayer(id: "p0", name: "Ada", deviceId: "d0", to: state)
    state = GameEngine.addPlayer(id: "p1", name: "Bea", deviceId: "d1", to: state)
    state = GameEngine.startRound(category: "Animals", in: state)

    for turn in 0..<2 {
      for i in 0..<2 {
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
    XCTAssertEqual(state.phase, .roundOver)
    return state
  }
}
