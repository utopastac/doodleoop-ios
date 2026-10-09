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

    let sheet = app.descendants(matching: .any)["rules-sheet"]
    XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Expected the rules sheet")

    let dismiss = app.buttons["sheet-dismiss"]
    XCTAssertTrue(dismiss.waitForExistence(timeout: 5), "Expected Done on rules sheet")
    dismiss.tap()
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

  @MainActor
  func testDrawingToolbarToolsDoNotCrash() {
    let app = launch(scene: .drawing)

    for tool in ["Pen", "Pencil", "Highlighter", "Eraser"] {
      let button = app.buttons[tool]
      XCTAssertTrue(button.waitForExistence(timeout: 5), "Expected \(tool) tool")
      button.tap()
      assertAlive(app)
    }

    // Nib sizes for the selected eraser (12 / 24 / 40 / 64).
    for nib in ["Nib 12", "Nib 24", "Nib 40", "Nib 64"] {
      let button = app.buttons[nib]
      XCTAssertTrue(button.waitForExistence(timeout: 3), "Expected \(nib)")
      button.tap()
      assertAlive(app)
    }

    let pen = app.buttons["Pen"]
    XCTAssertTrue(pen.waitForExistence(timeout: 3), "Expected Pen tool")
    pen.tap()
    assertAlive(app)

    for hex in ["#FFFFFF", "#000000", "#6176FF", "#EC6363"] {
      let swatch = app.buttons["Color \(hex)"]
      XCTAssertTrue(swatch.waitForExistence(timeout: 3), "Expected Color \(hex)")
      swatch.tap()
      assertAlive(app)
    }

    // Undo / Clear stay disabled on an empty canvas — tapping must still be safe.
    let undo = app.buttons["Undo"]
    XCTAssertTrue(undo.waitForExistence(timeout: 3), "Expected Undo")
    if undo.isEnabled { undo.tap() }
    assertAlive(app)

    let clear = app.buttons["Clear"]
    XCTAssertTrue(clear.waitForExistence(timeout: 3), "Expected Clear")
    if clear.isEnabled { clear.tap() }
    assertAlive(app)
  }

  @MainActor
  func testReconnectOverlayLeaveDoesNotCrash() {
    let app = launch(scene: .reconnect)
    let overlay = app.descendants(matching: .any)["reconnect-overlay"]
    XCTAssertTrue(overlay.waitForExistence(timeout: 5), "Expected reconnect overlay")
    // Overlay leave exits immediately — no confirmation dialog.
    let leave = app.buttons["leave-game"].firstMatch
    XCTAssertTrue(leave.waitForExistence(timeout: 5), "Expected Leave on reconnect overlay")
    leave.tap()
    assertAlive(app)
  }

  @MainActor
  func testHostMigrationOverlayLeaveDoesNotCrash() {
    let app = launch(scene: .hostMigration)
    let overlay = app.descendants(matching: .any)["host-migration-overlay"]
    XCTAssertTrue(overlay.waitForExistence(timeout: 5), "Expected host migration overlay")
    let leave = app.buttons["leave-game"].firstMatch
    XCTAssertTrue(leave.waitForExistence(timeout: 5), "Expected Leave on migration overlay")
    leave.tap()
    assertAlive(app)
  }

  @MainActor
  func testHandoffOverlayConfirmDoesNotCrash() {
    let app = launch(scene: .handoff)
    let overlay = app.descendants(matching: .any)["handoff-overlay"]
    XCTAssertTrue(overlay.waitForExistence(timeout: 5), "Expected handoff overlay")
    // Bracketed label is uppercased (`[ I'M CASEY ]`); identifier can be stripped by buttonStyle.
    let confirm = app.buttons.matching(
      NSPredicate(format: "label CONTAINS[c] %@", "I'M")
    ).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Expected handoff confirm")
    confirm.tap()
    assertAlive(app)
  }

  @MainActor
  func testHistoryDetailDoesNotCrash() {
    let app = launch(scene: .history)

    let item = app.descendants(matching: .any)["history-item"].firstMatch
    XCTAssertTrue(item.waitForExistence(timeout: 8), "Expected seeded history item")
    item.tap()
    assertAlive(app)

    let pad = app.descendants(matching: .any)["history-pad"].firstMatch
    XCTAssertTrue(pad.waitForExistence(timeout: 5), "Expected history pad row")
    pad.tap()
    assertAlive(app)

    let back = app.buttons["Back"].firstMatch
    if back.waitForExistence(timeout: 3) {
      back.tap()
      assertAlive(app)
    }

    let dismiss = app.buttons["sheet-dismiss"].firstMatch
    if dismiss.waitForExistence(timeout: 3) {
      dismiss.tap()
    } else if back.waitForExistence(timeout: 2) {
      back.tap()
    }
    assertAlive(app)
  }

  // MARK: - Helpers

  private enum Scene: String {
    case home = "01-home"
    case lobby = "02-lobby"
    case drawing = "03-drawing"
    case guessing = "04-guessing"
    case reveal = "05-reveal"
    case roundOver = "06-round-over"
    case reconnect = "07-reconnect"
    case hostMigration = "08-host-migration"
    case handoff = "09-handoff"
    case history = "10-history"
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
