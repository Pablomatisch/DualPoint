// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DualPoint",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DualPoint", targets: ["DualPoint"]),
        .executable(name: "DualPointDiagnose", targets: ["DualPointCLI"]),
        .executable(name: "DualPointSelfTest", targets: ["DualPointSelfTest"]),
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
        .executableTarget(
            name: "DualPointCLI",
            dependencies: ["DualPointCore"],
            path: "Sources/DualPointCLI"
        ),
        .executableTarget(
            name: "DualPointSelfTest",
            dependencies: ["DualPointCore"],
            path: "Tests/DualPointCoreTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
