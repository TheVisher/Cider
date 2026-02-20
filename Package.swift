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
            ],
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
