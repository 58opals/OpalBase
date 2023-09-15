// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OpalBase",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "OpalBase",
            targets: ["OpalBase"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.3.0"),
        .package(url: "https://github.com/Sajjon/K1.git", from: "0.3.9")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "OpalBase",
            dependencies: [
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "K1", package: "K1")
            ]
        ),
        .testTarget(
            name: "OpalBaseTests",
            dependencies: ["OpalBase"]),
    ]
)
