// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacFanControl",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacFanControl", targets: ["MacFanControl"])
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
        .testTarget(
            name: "MacFanControlTests",
            dependencies: ["MacFanControlCore"],
            path: "Tests/MacFanControlTests"
        )
    ]
)
