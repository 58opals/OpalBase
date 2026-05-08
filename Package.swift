// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OpalBase",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .watchOS(.v26),
        .tvOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(
            name: "OpalBase",
            targets: ["OpalBase"]),
    ],
    dependencies: [
        .package(url: "https://github.com/58opals/SwiftFulcrum.git", branch: "develop"),
        .package(url: "https://github.com/58opals/OpalCrypto.git", branch: "develop"),
        .package(url: "https://github.com/58opals/OpalFusion.git", branch: "develop"),
        .package(url: "https://github.com/58opals/OpalHedge.git", branch: "develop")
    ],
    targets: [
        .target(name: "OpalBase",
                dependencies: [
                    .product(name: "SwiftFulcrum", package: "SwiftFulcrum"),
                    .product(name: "OpalCrypto", package: "OpalCrypto"),
                    .product(
                        name: "OpalFusion",
                        package: "OpalFusion",
                        condition: .when(platforms: [.macOS])
                    ),
                    .product(name: "OpalHedge", package: "OpalHedge")
                ]
               ),
        .target(
            name: "OpalBaseTestSupport",
            dependencies: ["OpalBase"],
            path: "Tests/OpalBaseTestSupport"
        ),
        .testTarget(
            name: "OpalBaseLocalTests",
            dependencies: [
                "OpalBase",
                "OpalBaseTestSupport",
                .product(
                    name: "OpalFusion",
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
