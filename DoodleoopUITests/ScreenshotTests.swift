import XCTest

/// App Store screenshot capture. Run via `fastlane screenshots`.
///
/// Each test launches a deterministic `-UITScene` so chrome state is exact
/// (no flaky panel navigation).
final class ScreenshotTests: XCTestCase {
  @MainActor
  func test01Home() {
    capture(scene: .home, name: "01-Home")
  }

  @MainActor
  func test02Lobby() {
    capture(scene: .lobby, name: "02-Lobby")
  }

  @MainActor
  func test03Drawing() {
    capture(scene: .drawing, name: "03-Drawing")
  }

  @MainActor
  func test04Guessing() {
    capture(scene: .guessing, name: "04-Guessing")
  }

  @MainActor
  func test05Reveal() {
    capture(scene: .reveal, name: "05-Reveal")
  }

  @MainActor
  func test06RoundOver() {
    capture(scene: .roundOver, name: "06-RoundOver")
  }

  @MainActor
  private func capture(scene: Scene, name: String) {
    let app = XCUIApplication()
    setupSnapshot(app)
    app.launchArguments += [
      "-UITesting",
      "-UITScene", scene.rawValue,
    ]
    app.launch()

    let ready = app.descendants(matching: .any)["screenshot-ready"]
    XCTAssertTrue(
      ready.waitForExistence(timeout: 15),
      "Timed out waiting for screenshot-ready (\(scene.rawValue))"
    )

    // Brief settle so sheets / reveal animations finish.
    RunLoop.current.run(until: Date().addingTimeInterval(0.35))
    snapshot(name)
  }

  private enum Scene: String {
    case home = "01-home"
    case lobby = "02-lobby"
    case drawing = "03-drawing"
    case guessing = "04-guessing"
    case reveal = "05-reveal"
    case roundOver = "06-round-over"
  }
}
