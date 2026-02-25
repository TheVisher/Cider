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
            resources: [
                .copy("Resources/TipTapEditor"),
                .copy("Resources/ReaderMode"),
            ]
        ),
        // Thin CLI entry point — only used for `swift run`.
        // The Xcode project (Cider.xcodeproj) owns the .app build.
        .executableTarget(
            name: "CiderLauncher",
            dependencies: ["Cider"],
            path: "Sources/CiderApp",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Cider/Resources/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "CiderTests",
            dependencies: ["Cider"],
            path: "Tests/CiderTests"
        )
    ]
)
