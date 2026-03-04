// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-opa-sdk",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "SwiftOPASDK",
            targets: ["SwiftOPASDK"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/open-policy-agent/swift-opa", branch: "main"),
        .package(url: "https://github.com/swift-server/async-http-client", from: "1.21.0"),
        // TODO: Swap for whatever our solution ends up being. This is not the most recent commit,
        // but it is the last one that supports macOS 13 as a target.
        // Placeholder until we decide how to handle tar.gz wrangling:
        .package(
            url: "https://github.com/tsolomko/SWCompression", revision: "5b57ac0fcd78ccd9f42644a4cf7a379ec3821ef1"),
        .package(url: "https://github.com/jpsim/Yams", from: "6.2.1"),
    ],
    targets: [
        .target(
            name: "SwiftOPASDK",
            dependencies: [
                .product(name: "SwiftOPA", package: "swift-opa"),
                .product(name: "Yams", package: "Yams"),
                "Runtime",
            ]
        ),
        .target(
            name: "Config",
            dependencies: [
                .product(name: "SwiftOPA", package: "swift-opa")
            ],
            path: "Sources/Config"
        ),
        .target(
            name: "Runtime",
            dependencies: [
                "Config",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "SwiftOPA", package: "swift-opa"),
                .product(name: "SWCompression", package: "SWCompression"),
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/Runtime"
        ),
        .testTarget(
            name: "SwiftOPASDKTests",
            dependencies: ["SwiftOPASDK"]
        ),
        .testTarget(
            name: "RegoExtensionTests",
            dependencies: ["SwiftOPASDK"]
        ),
        .testTarget(
            name: "RuntimeTests",
            dependencies: ["Runtime"]
        ),
    ]
)
