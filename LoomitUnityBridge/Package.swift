// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LoomitUnityBridge",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "LoomitUnityBridge",
            type: .dynamic,
            targets: ["LoomitUnityBridge"]
        )
    ],
    dependencies: [
        .package(path: "../LoomitOfferwallAdapterAPI"),
        .package(path: "../LoomitOfferwallCore"),
        .package(path: "../LoomitOfferwallAdapterTapjoy"),
        .package(path: "../LoomitOfferwallAdapterMyChips"),
        .package(path: "../LoomitOfferwallDebug")
    ],
    targets: [
        .target(
            name: "LoomitUnityBridge",
            dependencies: [
                .product(name: "LoomitOfferwallCore", package: "LoomitOfferwallCore"),
                .product(name: "LoomitOfferwallAdapterAPI", package: "LoomitOfferwallAdapterAPI"),
                .product(name: "LoomitOfferwallAdapterTapjoy", package: "LoomitOfferwallAdapterTapjoy"),
                .product(name: "LoomitOfferwallAdapterMyChips", package: "LoomitOfferwallAdapterMyChips"),
                .product(name: "LoomitOfferwallDebug", package: "LoomitOfferwallDebug")
            ],
            path: "Sources/LoomitUnityBridge"
        )
    ],
    swiftLanguageVersions: [.v5]
)
