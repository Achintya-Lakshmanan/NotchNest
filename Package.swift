// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchNest",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchNest",
            path: "Sources/NotchNest",
            swiftSettings: [
                // AppKit + Timer-heavy code; opt out of Swift 6 strict concurrency.
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "NotchNestTests",
            dependencies: ["NotchNest"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
