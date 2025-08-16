// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OpalBase",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .watchOS(.v11),
        .tvOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "OpalBase",
            targets: ["OpalBase"]),
    ],
    dependencies: [
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.4.1"),
        .package(url: "https://github.com/58opals/SwiftFulcrum.git", from: "0.3.0"),
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1.git", from: "0.20.0")
    ],
    targets: [
        .target(name: "OpalBase",
                dependencies: [
                    .product(name: "BigInt", package: "BigInt"),
                    .product(name: "SwiftFulcrum", package: "SwiftFulcrum"),
                    .product(name: "P256K", package: "swift-secp256k1")
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
