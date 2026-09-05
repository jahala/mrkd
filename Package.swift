// swift-tools-version: 6.0

import Foundation
import PackageDescription

// The Mermaid renderer is a Rust cdylib built by scripts/build-mermaid.sh into
// Frameworks/libmermaid_shim.dylib. Xcode embeds one copy in the app bundle and
// both the app and the Quick Look extension find it through @rpath; a SwiftPM
// build has no bundle to embed into, so it gets an rpath straight to the repo.
// Absolute because the linker's working directory is not something SwiftPM
// promises. If the dylib is missing the link fails — deliberately, so a
// Mermaid-less build can never ship unnoticed.
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let frameworksDirectory = packageRoot.appendingPathComponent("Frameworks").path

let package = Package(
    name: "mrkd",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-cmark.git", branch: "gfm"),
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.2.0"),
        .package(url: "https://github.com/PhraseHQ/SwaTex.git", from: "0.5.0"),
    ],
    targets: [
        .systemLibrary(
            name: "CMermaid",
            path: "rust/mermaid-shim/include"
        ),
        .executableTarget(
            name: "mrkd",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
                .product(name: "Highlightr", package: "Highlightr"),
                .product(name: "SwaTex", package: "SwaTex"),
                .product(name: "SwaTexRender", package: "SwaTex"),
                "CMermaid",
            ],
            path: "Sources",
            exclude: [
                "Resources/Info.plist",
                "Resources/mrkd.entitlements",
                "Tests",
                "QLExtension",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Quartz"),
                .unsafeFlags([
                    "-L\(frameworksDirectory)",
                    "-Xlinker", "-rpath", "-Xlinker", frameworksDirectory,
                ]),
            ]
        ),
        .testTarget(
            name: "mrkdTests",
            // CMermaid so the tests can pin the C status codes against the
            // Swift failures they are supposed to map to. A drift there would
            // otherwise turn every render error into the wrong diagnosis.
            dependencies: ["mrkd", "CMermaid"],
            path: "Sources/Tests",
            // Same language mode as the target under test. Without this the
            // tests default to Swift 6 while the app stays on Swift 5, so
            // they are checked more strictly than the code they exercise --
            // and which AppKit constructs that rejects moves between
            // toolchains, which broke a release build on a Swift version
            // older than the one the tests were written against.
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
