import XCTest
@testable import Doodleoop

final class GameLimitsAndHelpersTests: XCTestCase {

  // MARK: - GamePartyLimits

  func testSanitizedNameTrimsCapsAndFallsBack() {
    XCTAssertEqual(GamePartyLimits.sanitizedName("  Ada  "), "Ada")
    XCTAssertEqual(GamePartyLimits.sanitizedName("   "), "Player")
    XCTAssertEqual(GamePartyLimits.sanitizedName("", fallback: "Guest"), "Guest")
    let long = String(repeating: "x", count: GamePartyLimits.maxNameLength + 10)
    XCTAssertEqual(GamePartyLimits.sanitizedName(long).count, GamePartyLimits.maxNameLength)
  }

  func testSanitizedGuessAndCategoryCapLength() {
    let guess = String(repeating: "g", count: GamePartyLimits.maxGuessLength + 5)
    XCTAssertEqual(GamePartyLimits.sanitizedGuess("  \(guess)  ").count, GamePartyLimits.maxGuessLength)

    let category = String(repeating: "c", count: GamePartyLimits.maxCategoryLength + 5)
    XCTAssertEqual(GamePartyLimits.sanitizedCategory("  \(category)  ").count, GamePartyLimits.maxCategoryLength)
    XCTAssertEqual(GamePartyLimits.sanitizedGuess("   "), "")
  }

  func testJoinCodeIsFourDigits() {
    for _ in 0..<20 {
      let code = GamePartyLimits.makeJoinCode()
      XCTAssertEqual(code.count, GamePartyLimits.joinCodeLength)
      XCTAssertTrue(code.allSatisfy(\.isNumber))
    }
  }

  func testPartyLimitConstants() {
    XCTAssertEqual(GamePartyLimits.maxPlayers, 12)
    XCTAssertEqual(GamePartyLimits.joinCodeLength, 4)
    XCTAssertEqual(GamePartyLimits.maxStrokesPerDrawing, 400)
    XCTAssertEqual(GamePartyLimits.maxPointsPerStroke, 1_500)
  }

  // MARK: - GameRoundDefaults.maxDraws

  func testMaxDrawsForPlayerCounts() {
    XCTAssertEqual(GameRoundDefaults.maxDraws(forPlayerCount: 0), GameRoundDefaults.minRounds)
    XCTAssertEqual(GameRoundDefaults.maxDraws(forPlayerCount: 3), 2)
    XCTAssertEqual(GameRoundDefaults.maxDraws(forPlayerCount: 4), 2)
    XCTAssertEqual(GameRoundDefaults.maxDraws(forPlayerCount: 5), 3)
    XCTAssertEqual(GameRoundDefaults.maxDraws(forPlayerCount: 8), 4)
    XCTAssertEqual(
      GameRoundDefaults.maxDraws(forPlayerCount: 40),
      GameRoundDefaults.absoluteMaxRounds
    )
  }

  // MARK: - RoundCategories

  func testRoundCategoriesAreUniqueAndNonEmpty() {
    XCTAssertFalse(RoundCategories.all.isEmpty)
    XCTAssertEqual(Set(RoundCategories.all).count, RoundCategories.all.count)
    XCTAssertTrue(RoundCategories.all.allSatisfy { !$0.isEmpty })
  }

  func testRoundCategoriesRandomExcludesCurrent() {
    let current = RoundCategories.all[0]
    for _ in 0..<30 {
      let next = RoundCategories.random(excluding: current)
      XCTAssertNotEqual(next.caseInsensitiveCompare(current), .orderedSame)
      XCTAssertTrue(RoundCategories.all.contains(next))
    }
  }

  // MARK: - PhaseCountdown

  @MainActor
  func testPhaseCountdownRemainingSeconds() {
    let now = Date(timeIntervalSince1970: 1_000)
    XCTAssertEqual(PhaseCountdown.remainingSeconds(until: nil, now: now), 0)
    XCTAssertEqual(
      PhaseCountdown.remainingSeconds(until: now.addingTimeInterval(45.1), now: now),
      46
    )
    XCTAssertEqual(
      PhaseCountdown.remainingSeconds(until: now.addingTimeInterval(-1), now: now),
      0
    )
  }

  @MainActor
  func testPhaseCountdownFormat() {
    XCTAssertEqual(PhaseCountdown.format(0), "00.00")
    XCTAssertEqual(PhaseCountdown.format(45), "00.45")
    XCTAssertEqual(PhaseCountdown.format(75), "01.15")
    XCTAssertEqual(PhaseCountdown.format(600), "10.00")
  }

  // MARK: - PhaseTimer

  func testPhaseTimerReturnsFalseWhenEndsAtNil() async {
    let finished = await PhaseTimer.waitForExpiry(endsAt: nil)
    XCTAssertFalse(finished)
  }

  func testPhaseTimerReturnsTrueForPastDeadline() async {
    let finished = await PhaseTimer.waitForExpiry(endsAt: Date().addingTimeInterval(-1))
    XCTAssertTrue(finished)
  }

  func testPhaseTimerCancellation() async {
    let task = Task {
      await PhaseTimer.waitForExpiry(endsAt: Date().addingTimeInterval(30))
    }
    task.cancel()
    let finished = await task.value
    XCTAssertFalse(finished)
  }

  // MARK: - DeviceIdentity

  func testDeviceIdentityPersistsAcrossCalls() {
    let suiteName = "doodleoop.tests.device-\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: suiteName)!
    defer { suite.removePersistentDomain(forName: suiteName) }

    let first = DeviceIdentity.current(defaults: suite)
    let second = DeviceIdentity.current(defaults: suite)
    XCTAssertFalse(first.isEmpty)
    XCTAssertEqual(first, second)
    XCTAssertNotNil(UUID(uuidString: first))
  }

  func testDeviceIdentityReusesExistingValue() {
    let suiteName = "doodleoop.tests.device-fixed-\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: suiteName)!
    defer { suite.removePersistentDomain(forName: suiteName) }
    suite.set("fixed-device-id", forKey: DeviceIdentity.defaultsKey)
    XCTAssertEqual(DeviceIdentity.current(defaults: suite), "fixed-device-id")
  }

  // MARK: - Avatar load

  @MainActor
  func testLoadAvatarFromDefaults() throws {
    let suiteName = "doodleoop.tests.avatar-\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: suiteName)!
    defer { suite.removePersistentDomain(forName: suiteName) }
    XCTAssertTrue(GameSession.loadAvatar(from: suite).isEmpty)

    let drawing = Drawing(strokes: [Stroke(points: [DrawPoint(x: 0.2, y: 0.3)])])
    suite.set(try JSONEncoder().encode(drawing), forKey: GameSession.avatarDefaultsKey)
    XCTAssertEqual(GameSession.loadAvatar(from: suite), drawing)

    suite.set(Data([0x00, 0x01]), forKey: GameSession.avatarDefaultsKey)
    XCTAssertTrue(GameSession.loadAvatar(from: suite).isEmpty)
  }

  // MARK: - MessageFraming

  func testMessageFramingRejectsOversizeLength() {
    var decoder = MessageFraming.Decoder()
    var header = Data()
    var length = UInt32(MessageFraming.maxPayloadSize + 1).bigEndian
    header.append(Data(bytes: &length, count: 4))
    XCTAssertThrowsError(try decoder.append(header)) { error in
      guard case MessageFraming.FramingError.invalidLength = error else {
        return XCTFail("expected invalidLength, got \(error)")
      }
    }
  }

  func testMessageFramingDecodesMultipleFrames() throws {
    var decoder = MessageFraming.Decoder()
    let a = Data("one".utf8)
    let b = Data("two".utf8)
    var blob = MessageFraming.encode(a)
    blob.append(MessageFraming.encode(b))
    XCTAssertEqual(try decoder.append(blob), [a, b])
  }

  // MARK: - RevealStep

  func testRevealStepListIdsAreStablePerPad() {
    let steps: [ChainStep] = [
      .prompt("Cats"),
      .drawing(playerId: "p0", drawing: .empty),
      .guess(playerId: "p1", text: "a cat"),
    ]
    let listed = RevealStep.list(steps, padIndex: 2)
    XCTAssertEqual(listed.map(\.id), [
      "pad2-step0",
      "pad2-step1",
      "pad2-step2",
    ])
    XCTAssertEqual(listed.map(\.index), [0, 1, 2])
    XCTAssertEqual(listed.map(\.step), steps)
  }
}
