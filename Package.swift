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
    ],
    dependencies: [
        .package(url: "https://github.com/58opals/SwiftFulcrum.git", revision: "3f92366e059b6a9bee6fb6abd87ee426d999ba12"),
        .package(url: "https://github.com/58opals/OpalCrypto.git", branch: "develop"),
        .package(url: "https://github.com/58opals/OpalFusion.git", branch: "develop"),
        .package(url: "https://github.com/58opals/OpalDiagnostics.git", branch: "develop")
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
                    .product(name: "OpalDiagnostics", package: "OpalDiagnostics")
                ]
               ),
        .testTarget(
            name: "OpalBaseTestSupport",
            dependencies: ["OpalBase"],
            path: "Tests/OpalBaseTestSupport"
        ),
        .testTarget(
            name: "OpalBaseLocalTests",
            dependencies: [
                "OpalBase",
                "OpalBaseTestSupport",
                .product(name: "OpalCrypto", package: "OpalCrypto"),
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
