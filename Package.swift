// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "OpalBase",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10),
        .tvOS(.v17),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "OpalBase",
            targets: ["OpalBase"]),
    ],
    dependencies: [
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.4.1"),
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1.git", from: "0.17.0"),
        .package(url: "https://github.com/58opals/SwiftFulcrum.git", from: "0.1.1")
    ],
    targets: [
        .target(name: "OpalBase",
                dependencies: [
                    .product(name: "BigInt", package: "BigInt"),
                    .product(name: "secp256k1", package: "swift-secp256k1"),
                    .product(name: "SwiftFulcrum", package: "SwiftFulcrum")
                ],
                resources: [
                    .process("Key/Hierarchical Deterministic/BIP-0039/English.txt"),
                    .process("Key/Hierarchical Deterministic/BIP-0039/Korean.txt")
                ]
               ),
        .testTarget(
            name: "OpalBaseTests",
            dependencies: ["OpalBase"]
        )
    ]
)
