// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Cider",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Cider", targets: ["Cider"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/get-convex/convex-swift", from: "0.8.1"),
    ],
    targets: [
        .target(
            name: "Cider",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "ConvexMobile", package: "convex-swift"),
            ],
            path: "Sources/Cider",
            exclude: [
                // Resources are bundled by the Xcode project (Cider.xcodeproj).
                // swift build is used for compilation verification only.
                "Resources/TipTapEditor",
                "Resources/ExcalidrawEditor",
                "Resources/ReaderMode",
                "Resources/Assets.xcassets",
                "Resources/Info.plist",
                "Resources/menubar-icon.png",
                "Resources/cider-icon.png",
            ]
        ),
        .testTarget(
            name: "CiderTests",
            dependencies: ["Cider"],
            path: "Tests/CiderTests"
        )
    ]
)
