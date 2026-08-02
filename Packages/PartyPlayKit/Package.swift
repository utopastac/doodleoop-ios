// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "PartyPlayKit",
  platforms: [
    .iOS(.v18),
    .macOS(.v14),
  ],
  products: [
    .library(name: "PartyPlayKit", targets: ["PartyPlayKit"]),
  ],
  targets: [
    .target(name: "PartyPlayKit"),
    .testTarget(
      name: "PartyPlayKitTests",
      dependencies: ["PartyPlayKit"]
    ),
  ]
)
