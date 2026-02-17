// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "mrkd",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-cmark.git", branch: "gfm"),
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "mrkd",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
                .product(name: "Highlightr", package: "Highlightr"),
            ],
            path: "Sources",
            exclude: ["Resources/Info.plist"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        ),
    ]
)
