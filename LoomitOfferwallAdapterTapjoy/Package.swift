// swift-tools-version:5.9
import PackageDescription

// LoomitOfferwallAdapterTapjoy
// Adapter para Tapjoy/Unity Offerwall (https://docs.unity.com/grow/offerwall/ios).
//
// El SDK Tapjoy iOS se distribuye via Swift Package Manager en
// https://github.com/Tapjoy/swift-packages.git; lo declaramos como dependencia
// directa de este target, de modo que cualquier publisher que integre este
// adapter automáticamente obtiene el SDK upstream.
let package = Package(
    name: "LoomitOfferwallAdapterTapjoy",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "LoomitOfferwallAdapterTapjoy",
            targets: ["LoomitOfferwallAdapterTapjoy"]
        )
    ],
    dependencies: [
        .package(path: "../LoomitOfferwallAdapterAPI"),
        .package(
            url: "https://github.com/Tapjoy/swift-packages.git",
            exact: "14.7.0"
        )
    ],
    targets: [
        .target(
            name: "LoomitOfferwallAdapterTapjoy",
            dependencies: [
                .product(name: "LoomitOfferwallAdapterAPI", package: "LoomitOfferwallAdapterAPI"),
                .product(name: "Tapjoy", package: "swift-packages")
            ],
            path: "Sources/LoomitOfferwallAdapterTapjoy"
        )
    ],
    swiftLanguageVersions: [.v5]
)
