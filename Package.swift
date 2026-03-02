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
        .package(url: "https://github.com/58opals/OpalCrypto.git", branch: "develop")
    ],
    targets: [
        .target(name: "OpalBase",
                dependencies: [
                    .product(name: "SwiftFulcrum", package: "SwiftFulcrum"),
                    .product(name: "OpalCrypto", package: "OpalCrypto")
                ],
                resources: [
                    .process("Resources/BIP-0039/English.txt"),
                    .process("Resources/BIP-0039/Korean.txt")
                ]
               ),
        .testTarget(
            name: "OpalBaseLocalTests",
            dependencies: ["OpalBase"],
            path: "Tests/OpalBaseTests",
            exclude: ["Network"]
        ),
        .testTarget(
            name: "OpalBaseNetworkTests",
            dependencies: ["OpalBase"],
            path: "Tests/OpalBaseTests",
            exclude: ["Local"]
        )
    ]
)
