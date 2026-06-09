// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LoomitOfferwallDebug",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "LoomitOfferwallDebug",
            targets: ["LoomitOfferwallDebug"]
        )
    ],
    dependencies: [
        .package(path: "../LoomitOfferwallCore")
    ],
    targets: [
        .target(
            name: "LoomitOfferwallDebug",
            dependencies: [
                .product(name: "LoomitOfferwallCore", package: "LoomitOfferwallCore")
            ],
            path: "Sources/LoomitOfferwallDebug"
        ),
        .testTarget(
            name: "LoomitOfferwallDebugTests",
            dependencies: ["LoomitOfferwallDebug"],
            path: "Tests/LoomitOfferwallDebugTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
