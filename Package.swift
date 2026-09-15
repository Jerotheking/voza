// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Voza",
    platforms: [.macOS(.v14)],
    // D032: the mlx-swift-examples dependency is GONE — local cleanup
    // inference was removed (see DECISIONS.md). Voza builds in seconds,
    // ships ~200 MB lighter, and owns zero resident LLM RAM.
    dependencies: [],
    targets: [
        .target(
            name: "VozaKit",
            path: "Sources/VozaKit"
        ),
        .executableTarget(
            name: "Voza",
            dependencies: ["VozaKit"],
            path: "Sources/Voza"
        ),
        .executableTarget(
            name: "VozaSmoke",
            dependencies: ["VozaKit"],
            path: "Sources/VozaSmoke"
        ),
        .testTarget(
            name: "VozaTests",
            dependencies: ["VozaKit"],
            path: "Tests/VozaTests"
        ),
    ]
)
