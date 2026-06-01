// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Cider",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Cider", targets: ["Cider"]),
        .executable(name: "cider-cli", targets: ["CiderCLI"])
    ],
    dependencies: [
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
        .testTarget(
            name: "CiderTests",
            dependencies: ["Cider", "CiderCLI"],
            path: "Tests/CiderTests"
        )
    ]
)
