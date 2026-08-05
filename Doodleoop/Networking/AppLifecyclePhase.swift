import Foundation

/// App lifecycle as observed by the UI — keeps SwiftUI out of networking types.
enum AppLifecyclePhase: Equatable {
  case active
  case inactive
  case background
}
