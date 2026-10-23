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
        .package(url: "https://github.com/58opals/SwiftFulcrum.git", revision: "43a1583270d8147111211f176d1d444db4a51aa9"),
        .package(url: "https://github.com/58opals/OpalCrypto.git", revision: "51fc53c50a66779ca23d564168351da8ecd00faf"),
        .package(url: "https://github.com/58opals/OpalFusion.git", revision: "b144a6ee03d5951eede74b54a59e106f29b8f944"),
        .package(url: "https://github.com/58opals/OpalDiagnostics.git", branch: "develop")
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
