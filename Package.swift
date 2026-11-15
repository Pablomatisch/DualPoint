// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DualPoint",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DualPoint", targets: ["DualPoint"]),
        .library(name: "DualPointCore", targets: ["DualPointCore"]),
    ],
    targets: [
        .target(
            name: "DualPointCore",
            path: "Sources/DualPointCore"
        ),
        .executableTarget(
            name: "DualPoint",
            dependencies: ["DualPointCore"],
            path: "Sources/DualPoint"
        ),
        .testTarget(
            name: "DualPointCoreTests",
            dependencies: ["DualPointCore"],
            path: "Tests/DualPointCoreTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
