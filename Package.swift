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
        .package(url: "https://github.com/58opals/SwiftFulcrum.git", revision: "6b4d062bb5ea6b61f2cc72f357427e5635c35128"),
        .package(url: "https://github.com/58opals/OpalCrypto.git", revision: "06f9edcbd5b44c869e6f81f3da1ea147add1d8cf"),
        .package(url: "https://github.com/58opals/OpalFusion.git", revision: "4c43ada607dc4a4cf52c0c3b5929bc201a535c57"),
        .package(url: "https://github.com/58opals/OpalDiagnostics.git", revision: "aa56dec5d6c8581beb2b3cef43b03dd577ccd9f1")
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
