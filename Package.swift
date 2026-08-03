// swift-tools-version: 6.0
//
// Mist — a modern, open-source tiling window manager for macOS.

import PackageDescription

let package = Package(
    name: "Mist",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Mist", targets: ["Mist"]),
        .library(name: "MistCore", targets: ["MistCore"])
    ],
    targets: [
        .target(name: "MistCore"),
        .executableTarget(name: "Mist", dependencies: ["MistCore"]),
        .testTarget(name: "MistCoreTests", dependencies: ["MistCore"])
    ]
)