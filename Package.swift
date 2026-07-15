// swift-tools-version: 6.0
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let infoPlistPath = packageRoot
    .appendingPathComponent("Sources/CodexFloat/Info.plist")
    .path

let package = Package(
    name: "CodexFloat",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexFloat", targets: ["CodexFloat"]),
        .library(name: "CodexFloatCore", targets: ["CodexFloatCore"])
    ],
    targets: [
        .target(
            name: "CodexFloatCore",
            path: "Sources/CodexFloatCore"
        ),
        .executableTarget(
            name: "CodexFloat",
            dependencies: ["CodexFloatCore"],
            path: "Sources/CodexFloat",
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed Info.plist so Xcode runs get a real bundle id (LSUIElement menu-bar app).
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlistPath
                ], .when(platforms: [.macOS]))
            ]
        ),
        // Full XCTest suite needs Xcode. Until then, use:
        //   swift run CodexFloatCoreSmokeTests
        .executableTarget(
            name: "CodexFloatCoreSmokeTests",
            dependencies: ["CodexFloatCore"],
            path: "Tests/CodexFloatCoreSmokeTests"
        )
    ]
)
