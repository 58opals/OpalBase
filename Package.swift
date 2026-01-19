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
        .package(url: "https://github.com/58opals/SwiftFulcrum.git", from: "0.5.0"),
        .package(url: "https://github.com/58opals/SwiftSchnorr.git", branch: "draft")
    ],
    targets: [
        .target(name: "OpalBase",
                dependencies: [
                    .product(name: "SwiftFulcrum", package: "SwiftFulcrum"),
                    .product(name: "SwiftSchnorr", package: "SwiftSchnorr")
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
