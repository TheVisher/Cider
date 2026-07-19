// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Cider",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Cider", targets: ["Cider"]),
        .executable(name: "cider-cli", targets: ["CiderCLI"]),
        .executable(name: "cider-db-maintenance", targets: ["CiderDatabaseMaintenance"])
    ],
    dependencies: [
        .package(name: "CID850Interpose", path: "Tests/CID850Interpose"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm/", .upToNextMinor(from: "2.29.1")),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3"),
    ],
    targets: [
        .target(
            name: "Cider",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/Cider",
            exclude: [
                // Resources are bundled by the Xcode project (Cider.xcodeproj).
                // swift build is used for compilation verification only.
                "Resources/TipTapEditor",
                "Resources/ReaderMode",
                "Resources/Assets.xcassets",
                "Resources/Info.plist",
                "Resources/menubar-icon.png",
                "Resources/cider-icon.png",
            ]
        ),
        .executableTarget(
            name: "CiderCLI",
            dependencies: ["Cider"],
            path: "Sources/CiderCLI",
            swiftSettings: [.unsafeFlags(["-enable-testing"])]
        ),
        .executableTarget(
            name: "CiderDatabaseMaintenance",
            dependencies: ["Cider"],
            path: "Sources/CiderDatabaseMaintenance"
        ),
        .executableTarget(
            name: "CID850BoundaryHarness",
            dependencies: [
                "Cider",
                .product(name: "CID850Interpose", package: "CID850Interpose"),
            ],
            path: "Tests/CID850BoundaryHarness",
            swiftSettings: [.unsafeFlags(["-enable-testing"])]
        ),
        .executableTarget(
            name: "CID868MaintenanceHarness",
            dependencies: ["Cider"],
            path: "Tests/CID868MaintenanceHarness",
            swiftSettings: [.unsafeFlags(["-enable-testing"])]
        ),
        .testTarget(
            name: "CiderTests",
            dependencies: [
                "Cider",
                "CiderCLI",
                "CiderDatabaseMaintenance",
                "CID850BoundaryHarness",
                "CID868MaintenanceHarness",
            ],
            path: "Tests/CiderTests"
        )
    ]
)
