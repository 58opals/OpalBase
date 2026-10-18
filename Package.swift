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
        .package(url: "https://github.com/58opals/SwiftFulcrum.git", revision: "154c4b693a75ea746f2a792177f200b501aa4a99"),
        .package(url: "https://github.com/58opals/OpalCrypto.git", branch: "develop"),
        .package(url: "https://github.com/58opals/OpalFusion.git", revision: "ff1c14934ee4b0562f4726eb81d7438cab4f0f85"),
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
