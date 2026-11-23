// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MouseHelper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MouseHelper", targets: ["MouseHelper"])
    ],
    targets: [
        .target(
            name: "MouseHelperCore",
            path: "Sources/MouseHelperCore"
        ),
        .executableTarget(
            name: "MouseHelper",
            dependencies: ["MouseHelperCore"],
            path: "Sources/MouseHelper"
        ),
        .testTarget(
            name: "MouseHelperCoreTests",
            dependencies: ["MouseHelperCore"],
            path: "Tests/MouseHelperCoreTests"
        )
    ]
)
