// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LoomitOfferwallAdapterAPI",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "LoomitOfferwallAdapterAPI",
            targets: ["LoomitOfferwallAdapterAPI"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LoomitOfferwallAdapterAPI",
            path: "Sources/LoomitOfferwallAdapterAPI"
        ),
        .testTarget(
            name: "LoomitOfferwallAdapterAPITests",
            dependencies: ["LoomitOfferwallAdapterAPI"],
            path: "Tests/LoomitOfferwallAdapterAPITests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
