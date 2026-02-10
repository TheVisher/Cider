// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Cider",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Cider", targets: ["Cider"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Cider",
            path: "Sources/Cider",
            resources: [
                .copy("Resources/TipTapEditor")
            ]
        ),
        .testTarget(
            name: "CiderTests",
            dependencies: ["Cider"],
            path: "Tests/CiderTests"
        )
    ]
)
