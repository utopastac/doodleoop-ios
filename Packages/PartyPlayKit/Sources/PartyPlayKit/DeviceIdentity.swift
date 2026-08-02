import Foundation

/// Stable phone identity used to map Multipeer peers to seats.
/// Multiple local seats share one `deviceId`.
public enum DeviceIdentity {
  public static let defaultsKey = "partyPlay.deviceId"

  /// Returns a persisted UUID string, creating one on first launch.
  public static func current(defaults: UserDefaults = .standard) -> String {
    if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
      return existing
    }
    let created = UUID().uuidString
    defaults.set(created, forKey: defaultsKey)
    return created
  }
}
