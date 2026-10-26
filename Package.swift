// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "OpalBase",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .watchOS(.v27),
        .tvOS(.v27),
        .visionOS(.v27)
    ],
    products: [
        .library(
            name: "OpalBase",
            targets: ["OpalBase"]),
        .library(name: "OpalBaseCore", targets: ["OpalBaseCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/58opals/SwiftFulcrum.git", revision: "98ffddf6c7212b40e52c20f9876d61de9e9c25a1"),
        .package(url: "https://github.com/58opals/OpalCrypto.git", revision: "0adfc220b30dfc9512bb8a45c1e4e6033e8bd95a"),
        .package(url: "https://github.com/58opals/OpalFusion.git", revision: "1b1cf34a5d96d60f424459813d5fd8e9a0b3e72b"),
        .package(url: "https://github.com/58opals/OpalDiagnostics.git", revision: "4147c6191a4d25624c4f4f7e4e97eaeb8010a8fd")
    ],
    targets: [
        .testTarget(name: "OpalBaseCoreTests", dependencies: ["OpalBaseCore"], path: "Tests/OpalBaseCoreTests"),
        .target(name: "OpalBaseCore",
                dependencies: [
                    .product(name: "SwiftFulcrum", package: "SwiftFulcrum"),
                    .product(name: "OpalCrypto", package: "OpalCrypto"),
                    .product(name: "OpalDiagnostics", package: "OpalDiagnostics")
                ], path: "Sources/OpalBase"
               ),
        .target(name: "OpalBase", dependencies: ["OpalBaseCore", .product(name: "OpalCrypto", package: "OpalCrypto"), .product(name: "OpalDiagnostics", package: "OpalDiagnostics"), .product(name: "OpalFusion", package: "OpalFusion", condition: .when(platforms: [.macOS]))], path: "Sources/OpalBaseCompatibility"),
        .testTarget(
            name: "OpalBaseTestSupport",
            dependencies: ["OpalBase", "OpalBaseCore"],
            path: "Tests/OpalBaseTestSupport"
        ),
        .testTarget(
            name: "OpalBaseLocalTests",
            dependencies: [
                "OpalBase",
                "OpalBaseCore",
                "OpalBaseTestSupport",
                .product(name: "OpalCrypto", package: "OpalCrypto"),
                .product(
                    name: "OpalFusion",
                    package: "OpalFusion",
                    condition: .when(platforms: [.macOS])
                ),
                .product(
                    name: "CashFusionEngine",
                    package: "OpalFusion",
                    condition: .when(platforms: [.macOS])
                ),
                .product(
                    name: "MosaicEngine",
                    package: "OpalFusion",
                    condition: .when(platforms: [.macOS])
                )
            ],
            path: "Tests/OpalBaseLocalTests"
        ),
        .testTarget(
            name: "OpalBaseNetworkTests",
            dependencies: ["OpalBase", "OpalBaseTestSupport"],
            path: "Tests/OpalBaseNetworkTests"
        )
    ]
)
