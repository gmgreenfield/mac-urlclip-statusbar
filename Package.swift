// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "UrlClipStatusBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "UrlClipStatusBar", targets: ["UrlClipStatusBar"]),
        .library(name: "UrlClipCore", targets: ["UrlClipCore"])
    ],
    targets: [
        .target(
            name: "UrlClipCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "UrlClipStatusBar",
            dependencies: ["UrlClipCore"]
        ),
        .testTarget(
            name: "UrlClipCoreTests",
            dependencies: ["UrlClipCore"]
        )
    ]
)
