// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CID850Interpose",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "CID850Interpose",
            type: .dynamic,
            targets: ["CID850Interpose"]
        ),
    ],
    targets: [
        .target(
            name: "CID850Interpose",
            path: ".",
            exclude: ["Package.swift"],
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
    ]
)
