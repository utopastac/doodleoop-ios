import XCTest
@testable import Doodleoop

@MainActor
final class UITestingContractTests: XCTestCase {
  func testArgumentParsing() {
    XCTAssertFalse(UITesting.isEnabled(arguments: ["-Foo"]))
    XCTAssertTrue(UITesting.isEnabled(arguments: [UITesting.argument]))

    XCTAssertNil(UITesting.scene(from: [UITesting.argument]))
    XCTAssertNil(UITesting.scene(from: [UITesting.sceneArgument, "-UITesting"]))
    XCTAssertEqual(
      UITesting.scene(from: [UITesting.argument, UITesting.sceneArgument, "03-drawing"]),
      "03-drawing"
    )
    XCTAssertEqual(
      UITesting.parsedScene(from: [UITesting.sceneArgument, "05-reveal"]),
      .reveal
    )
    XCTAssertNil(UITesting.parsedScene(from: [UITesting.sceneArgument, "not-a-scene"]))
  }

  func testEverySceneMapsToExpectedPreviewOrNil() {
    let expected: [UITesting.Scene: ViewPreview?] = [
      .home: nil,
      .lobby: .lobbyNearbyHost,
      .drawing: .drawing,
      .guessing: .guessing,
      .reveal: .reveal,
      .roundOver: .roundOver,
      .reconnect: .reconnecting,
      .hostMigration: .hostMigration,
      .handoff: .handoffOverlay,
      .history: nil,
    ]
    for scene in UITesting.Scene.allCases {
      XCTAssertEqual(
        UITesting.viewPreview(for: scene),
        expected[scene] ?? nil,
        "Unexpected preview for \(scene.rawValue)"
      )
    }
  }

  func testPreviewFactoryPhases() {
    let device = "device-1"
    let avatar = PreviewStateFactory.demoDrawing(seed: 1)

    let lobby = PreviewStateFactory.makeLobby(
      playerCount: 4,
      sharedDevice: false,
      devicePlayerId: device,
      displayName: "Blake",
      avatar: avatar
    )
    XCTAssertEqual(lobby.phase, .lobby)
    XCTAssertEqual(lobby.players.count, 4)

    let drawing = PreviewStateFactory.drawingState(
      devicePlayerId: device,
      displayName: "Blake",
      avatar: avatar
    )
    XCTAssertEqual(drawing.phase, .drawing)

    let guessing = PreviewStateFactory.guessingState(
      devicePlayerId: device,
      displayName: "Blake",
      avatar: avatar
    )
    XCTAssertEqual(guessing.phase, .guessing)

    let reveal = PreviewStateFactory.revealState(
      devicePlayerId: device,
      displayName: "Blake",
      avatar: avatar
    )
    XCTAssertEqual(reveal.phase, .reveal)

    let roundOver = PreviewStateFactory.roundOverState(
      devicePlayerId: device,
      displayName: "Blake",
      avatar: avatar
    )
    XCTAssertEqual(roundOver.phase, .roundOver)
  }

  func testLoadPreviewOverlayFlags() throws {
    let store = try makeHistoryStore()
    let session = GameSession(historyStore: store, deviceId: "host-device")

    session.loadPreview(.reconnecting)
    XCTAssertEqual(session.role, .joiner)
    XCTAssertTrue(session.isReconnecting)
    XCTAssertFalse(session.testing_isMigratingHost)
    XCTAssertEqual(session.state?.phase, .drawing)

    session.loadPreview(.hostMigration)
    XCTAssertEqual(session.role, .joiner)
    XCTAssertTrue(session.testing_isMigratingHost)
    XCTAssertFalse(session.isReconnecting)

    session.loadPreview(.handoffOverlay)
    XCTAssertEqual(session.role, .host)
    XCTAssertNotNil(session.handoff)
    XCTAssertEqual(session.handoff?.title, "Pass the phone")
  }

  func testSharedDevicePreviewKeepsOneDeviceId() {
    let players = PreviewStateFactory.makePlayers(
      count: 4,
      sharedDevice: true,
      devicePlayerId: "phone",
      displayName: "Blake",
      avatar: .empty
    )
    XCTAssertEqual(Set(players.map(\.deviceId)), ["phone"])
  }

  private func makeHistoryStore() throws -> GameHistoryStore {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("doodleoop-uit-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return GameHistoryStore(directory: dir)
  }
}
