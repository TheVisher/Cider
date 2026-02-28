// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Cider",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Cider", targets: ["Cider"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Cider",
            path: "Sources/Cider",
            exclude: [
                // Resources are bundled by the Xcode project (Cider.xcodeproj).
                // swift build is used for compilation verification only.
                "Resources/TipTapEditor",
                "Resources/ReaderMode",
                "Resources/Assets.xcassets",
            ]
        ),
        .testTarget(
            name: "CiderTests",
            dependencies: ["Cider"],
            path: "Tests/CiderTests"
        )
    ]
)
