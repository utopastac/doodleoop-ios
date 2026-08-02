import Foundation

/// Stable phone identity used to map Multipeer peers to seats.
/// Multiple local seats share one `deviceId`.
enum DeviceIdentity {
  static let defaultsKey = "doodleoop.deviceId"

  /// Returns a persisted UUID string, creating one on first launch.
  static func current(defaults: UserDefaults = .standard) -> String {
    if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
      return existing
    }
    let created = UUID().uuidString
    defaults.set(created, forKey: defaultsKey)
    return created
  }
}
