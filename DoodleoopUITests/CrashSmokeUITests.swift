import XCTest

/// Process-survival smoke tests. Launch seeded `-UITesting` scenes, poke the main
/// crash surfaces, and assert the app is still running.
///
/// These are intentionally shallow — they catch SwiftUI first-paint / first-tap
/// crashes, not visual regressions (see `ScreenshotTests`) or domain logic
/// (see `DoodleoopTests`).
final class CrashSmokeUITests: XCTestCase {
  // MARK: - First paint

  @MainActor
  func testHomeSceneLaunchesWithoutCrashing() {
    assertSceneLaunches(.home)
  }

  @MainActor
  func testLobbySceneLaunchesWithoutCrashing() {
    assertSceneLaunches(.lobby)
  }

  @MainActor
  func testDrawingSceneLaunchesWithoutCrashing() {
    assertSceneLaunches(.drawing)
  }

  @MainActor
  func testGuessingSceneLaunchesWithoutCrashing() {
    assertSceneLaunches(.guessing)
  }

  @MainActor
  func testRevealSceneLaunchesWithoutCrashing() {
    assertSceneLaunches(.reveal)
  }

  @MainActor
  func testRoundOverSceneLaunchesWithoutCrashing() {
    assertSceneLaunches(.roundOver)
  }

  // MARK: - Interactions

  @MainActor
  func testTheRulesAndDismissDoesNotCrash() {
    let app = launch(scene: .home)

    let rules = app.buttons["the-rules"]
    XCTAssertTrue(rules.waitForExistence(timeout: 5), "Expected The rules on home")
    rules.tap()
    assertAlive(app)

    let gotIt = app.alerts.buttons["Got it"]
    XCTAssertTrue(gotIt.waitForExistence(timeout: 5), "Expected Got it on rules alert")
    gotIt.tap()
    assertAlive(app)
  }

  @MainActor
  func testSettingsAndDismissDoesNotCrash() {
    let app = launch(scene: .home)

    let settings = app.buttons["settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5), "Expected Settings on home")
    settings.tap()
    assertAlive(app)

    let dismiss = app.buttons["sheet-dismiss"]
    XCTAssertTrue(dismiss.waitForExistence(timeout: 5), "Expected Done on settings sheet")
    dismiss.tap()
    assertAlive(app)
  }

  @MainActor
  func testHistoryAndBackDoesNotCrash() {
    let app = launch(scene: .home)

    let history = app.buttons["history"]
    XCTAssertTrue(history.waitForExistence(timeout: 5), "Expected History on home")
    history.tap()
    assertAlive(app)

    // History uses the shared sheet header Done control (not a nav back arrow).
    let dismiss = app.buttons["sheet-dismiss"]
    XCTAssertTrue(dismiss.waitForExistence(timeout: 5), "Expected Done on history")
    dismiss.tap()
    assertAlive(app)
  }

  @MainActor
  func testHostGameDoesNotCrash() {
    let app = launch(scene: .home)

    let host = app.buttons["host-game"]
    XCTAssertTrue(host.waitForExistence(timeout: 5), "Expected Host on home")
    host.tap()
    assertAlive(app)

    // Live host lands in lobby — leave so we exercise that path too.
    leaveGame(in: app, hostEnds: true)
  }

  @MainActor
  func testLobbyAddPlayerDoesNotCrash() {
    let app = launch(scene: .lobby)

    let add = app.buttons["add-player"]
    XCTAssertTrue(add.waitForExistence(timeout: 5), "Expected Add player in lobby")
    add.tap()
    assertAlive(app)
  }

  @MainActor
  func testLobbyStartGameSheetDoesNotCrash() {
    let app = launch(scene: .lobby)

    let start = app.buttons["start-game"]
    XCTAssertTrue(start.waitForExistence(timeout: 5), "Expected Start game on host lobby")
    start.tap()
    assertAlive(app)

    let cancel = app.buttons["Cancel"]
    XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Expected Cancel on category sheet")
    cancel.tap()
    assertAlive(app)
  }

  @MainActor
  func testLobbyLeaveDoesNotCrash() {
    let app = launch(scene: .lobby)
    leaveGame(in: app, hostEnds: true)

    let host = app.buttons["host-game"]
    XCTAssertTrue(host.waitForExistence(timeout: 10), "Expected home after leave")
    assertAlive(app)
  }

  @MainActor
  func testRevealAdvanceDoesNotCrash() {
    let app = launch(scene: .reveal)

    let advance = app.buttons["advance-reveal"]
    XCTAssertTrue(advance.waitForExistence(timeout: 5), "Expected reveal advance on host")
    advance.tap()
    assertAlive(app)
  }

  @MainActor
  func testDrawingLeaveDoesNotCrash() {
    let app = launch(scene: .drawing)
    leaveGame(in: app, hostEnds: true)
  }

  // MARK: - Helpers

  private enum Scene: String {
    case home = "01-home"
    case lobby = "02-lobby"
    case drawing = "03-drawing"
    case guessing = "04-guessing"
    case reveal = "05-reveal"
    case roundOver = "06-round-over"
  }

  @MainActor
  private func assertSceneLaunches(_ scene: Scene) {
    let app = launch(scene: scene)
    assertAlive(app)
  }

  @MainActor
  private func launch(scene: Scene) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
      "-UITesting",
      "-UITScene", scene.rawValue,
    ]
    app.launch()

    let ready = app.descendants(matching: .any)["screenshot-ready"]
    XCTAssertTrue(
      ready.waitForExistence(timeout: 15),
      "Timed out waiting for screenshot-ready (\(scene.rawValue))"
    )
    assertAlive(app)
    return app
  }

  @MainActor
  private func assertAlive(_ app: XCUIApplication) {
    // Under XCUITest the app often reports a non-foreground running state (rawValue 3)
    // even when healthy. Only treat notRunning / unknown as a crash signal.
    XCTAssertNotEqual(app.state, .notRunning, "App is not running — likely crashed")
    XCTAssertNotEqual(app.state, .unknown, "App state unknown — likely crashed")
  }

  @MainActor
  private func leaveGame(in app: XCUIApplication, hostEnds: Bool) {
    let leave = app.buttons["leave-game"].firstMatch
    XCTAssertTrue(leave.waitForExistence(timeout: 8), "Expected Leave game")
    leave.tap()
    assertAlive(app)

    let confirmLabel = hostEnds ? "End game" : "Leave game"
    // confirmationDialog can expose duplicate button nodes under XCUITest.
    let confirm = app.buttons[confirmLabel].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Expected \(confirmLabel) confirmation")
    confirm.tap()
    assertAlive(app)
  }
}
