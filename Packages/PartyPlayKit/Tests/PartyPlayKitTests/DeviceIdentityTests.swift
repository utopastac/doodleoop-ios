import XCTest
@testable import PartyPlayKit

final class DeviceIdentityTests: XCTestCase {
  func testPersistsStableId() {
    let suite = "PartyPlayKitTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let first = DeviceIdentity.current(defaults: defaults)
    let second = DeviceIdentity.current(defaults: defaults)
    XCTAssertEqual(first, second)
    XCTAssertFalse(first.isEmpty)
  }
}
