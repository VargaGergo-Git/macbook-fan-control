// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacFanControl",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacFanControl", targets: ["MacFanControl"]),
        .executable(name: "MacFanControlHelper", targets: ["MacFanControlHelper"])
    ],
    targets: [
        .target(
            name: "MacFanControlCore",
            path: "Sources/MacFanControlCore"
        ),
        .executableTarget(
            name: "MacFanControl",
            dependencies: ["MacFanControlCore"],
            path: "Sources/MacFanControl"
        ),
        .executableTarget(
            name: "MacFanControlHelper",
            dependencies: ["MacFanControlCore"],
            path: "Sources/MacFanControlHelper"
        ),
        .testTarget(
            name: "MacFanControlTests",
            dependencies: ["MacFanControlCore"],
            path: "Tests/MacFanControlTests"
        )
    ]
)
