// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Voza",
    platforms: [.macOS(.v14)],
    dependencies: [
        // D024: in-process cleanup inference — removes the Ollama adoption
        // requirement. Pinned to a release line, not a branch.
        .package(
            url: "https://github.com/ml-explore/mlx-swift-examples.git",
            from: "2.0.0"
        ),
    ],
    targets: [
        .target(
            name: "VozaKit",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
            ],
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
        .executableTarget(
            name: "MLXBench",
            dependencies: ["VozaKit"],
            path: "Sources/MLXBench"
        ),
        .testTarget(
            name: "VozaTests",
            dependencies: ["VozaKit"],
            path: "Tests/VozaTests"
        ),
    ]
)
