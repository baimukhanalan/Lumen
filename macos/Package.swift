// swift-tools-version:6.0
//
// SwiftPM manifest for Lumen (macOS).
//
// NOTE: The authoritative, CLT-only build is `macos/build.sh`, which drives
// `swiftc` directly and assembles `build/Lumen.app`. This manifest mirrors the
// same source layout for editor/IDE tooling and `swift build`. It pins the
// Swift 5 language mode so behavior matches the script build (and to keep the
// AppKit/SwiftUI main-thread code free of strict-concurrency churn).
//
// `swift build` here produces the two executables (`Lumen`, `lumen-daemon`)
// but does NOT assemble the .app bundle — use build.sh for that.

import PackageDescription

let package = Package(
    name: "Lumen",
    platforms: [.macOS(.v12)],
    targets: [
        .target(
            name: "LumenCore",
            path: "Sources/LumenCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "lumen-daemon",
            dependencies: ["LumenCore"],
            path: "Sources/LumenDaemon",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Lumen",
            dependencies: ["LumenCore"],
            path: "Sources/Lumen",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
