// swift-tools-version: 6.2

import PackageDescription

let approachableConcurrencySettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .defaultIsolation(MainActor.self),
]

let package = Package(
    name: "axPackage",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AXorcist", targets: ["AXorcist"]),
        .executable(name: "axorc", targets: ["axorc"]),
    ],
    dependencies: [
        .package(url: "https://github.com/steipete/Commander.git", exact: "0.2.4"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.15.1"),
    ],
    targets: [
        .target(
            name: "AXorcist",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/AXorcist",
            swiftSettings: approachableConcurrencySettings
        ),
        .executableTarget(
            name: "axorc",
            dependencies: [
                "AXorcist",
                .product(name: "Commander", package: "Commander"),
            ],
            path: "Sources/axorc",
            swiftSettings: approachableConcurrencySettings
        ),
        .testTarget(
            name: "AXorcistTests",
            dependencies: [
                "AXorcist",
                "axorc",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Tests/AXorcistTests",
            swiftSettings: approachableConcurrencySettings
        ),
        .testTarget(
            name: "AXorcistCommandConversionTests",
            dependencies: ["AXorcist", "axorc"],
            path: "Tests/AXorcistCommandConversionTests",
            swiftSettings: approachableConcurrencySettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
