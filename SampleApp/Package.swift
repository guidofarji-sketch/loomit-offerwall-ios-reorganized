// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LoomitOfferwallSampleApp",
    platforms: [
        .iOS(.v15)
    ],
    dependencies: [
        .package(path: "../LoomitOfferwallCore"),
        .package(path: "../LoomitOfferwallAdapterMyChips"),
        .package(path: "../LoomitOfferwallAdapterTapjoy"),
        .package(path: "../LoomitOfferwallDebug"),
        .package(
            url: "https://github.com/myappfree/mychips-ios-sdk",
            from: "1.1.0"
        )
    ],
    targets: [
        .target(
            name: "LoomitOfferwallSampleApp",
            dependencies: [
                .product(name: "LoomitOfferwallCore", package: "LoomitOfferwallCore"),
                .product(name: "LoomitOfferwallAdapterMyChips", package: "LoomitOfferwallAdapterMyChips"),
                .product(name: "LoomitOfferwallAdapterTapjoy", package: "LoomitOfferwallAdapterTapjoy"),
                .product(name: "LoomitOfferwallDebug", package: "LoomitOfferwallDebug"),
                .product(name: "MyChipsSdk", package: "mychips-ios-sdk")
            ],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
