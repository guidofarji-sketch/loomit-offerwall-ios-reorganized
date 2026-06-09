// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LoomitOfferwallCore",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "LoomitOfferwallCore",
            targets: ["LoomitOfferwallCore"]
        )
    ],
    dependencies: [
        .package(path: "../LoomitOfferwallAdapterAPI"),
        .package(path: "../LoomitOfferwallAdapterMyChips")
    ],
    targets: [
        .target(
            name: "LoomitOfferwallCore",
            dependencies: [
                .product(name: "LoomitOfferwallAdapterAPI", package: "LoomitOfferwallAdapterAPI")
            ],
            path: "Sources/LoomitOfferwallCore"
        ),
        .testTarget(
            name: "LoomitOfferwallCoreTests",
            dependencies: [
                "LoomitOfferwallCore",
                .product(name: "LoomitOfferwallAdapterMyChips", package: "LoomitOfferwallAdapterMyChips")
            ],
            path: "Tests/LoomitOfferwallCoreTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
