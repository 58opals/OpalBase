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
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.7.0"),
        .package(url: "https://github.com/58opals/SwiftFulcrum.git", from: "0.4.0"),
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1.git", from: "0.21.0")
    ],
    targets: [
        .target(name: "OpalBase",
                dependencies: [
                    .product(name: "BigInt", package: "BigInt"),
                    .product(name: "SwiftFulcrum", package: "SwiftFulcrum"),
                    .product(name: "P256K", package: "swift-secp256k1")
                ],
                resources: [
                    .process("(Resource)/BIP-0039/English.txt"),
                    .process("(Resource)/BIP-0039/Korean.txt")
                ]
               ),
        .testTarget(
            name: "OpalBaseTests",
            dependencies: ["OpalBase"]
        )
    ]
)
