// swift-tools-version:5.9
import PackageDescription

// LoomitOfferwallAdapterMyChips
// Adapter para MyChips/MAF Offerwall (https://docs.mychips.io/ios/install-sdk).
//
// El SDK MyChips iOS se distribuye via SPM en
// https://github.com/myappfree/mychips-ios-sdk; lo declaramos como dependencia
// directa de este target, de modo que cualquier publisher que integre este
// adapter automáticamente obtiene el SDK upstream.
let package = Package(
    name: "LoomitOfferwallAdapterMyChips",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "LoomitOfferwallAdapterMyChips",
            targets: ["LoomitOfferwallAdapterMyChips"]
        )
    ],
    dependencies: [
        .package(path: "../LoomitOfferwallAdapterAPI"),
        .package(
            url: "https://github.com/myappfree/mychips-ios-sdk",
            from: "1.1.0"
        )
    ],
    targets: [
        .target(
            name: "LoomitOfferwallAdapterMyChips",
            dependencies: [
                .product(name: "LoomitOfferwallAdapterAPI", package: "LoomitOfferwallAdapterAPI"),
                .product(name: "MyChipsSdk", package: "mychips-ios-sdk")
            ],
            path: "Sources/LoomitOfferwallAdapterMyChips"
        ),
        .testTarget(
            name: "LoomitOfferwallAdapterMyChipsTests",
            dependencies: ["LoomitOfferwallAdapterMyChips"],
            path: "Tests/LoomitOfferwallAdapterMyChipsTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
