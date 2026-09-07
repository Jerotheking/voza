// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Voza",
    platforms: [.macOS(.v14)],
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
