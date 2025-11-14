![Swift 6.2](https://img.shields.io/badge/swift-6.2-orange)
![SPM](https://img.shields.io/badge/Package%20Manager-SPM-informational)
![Platforms](https://img.shields.io/badge/platforms-iOS%20|%20macOS%20|%20watchOS%20|%20tvOS%20|%20visionOS-blue)

# Opal Base

## Introduction

**Opal Base** is an open-source Swift library designed to help developers within the Apple ecosystem seamlessly integrate Bitcoin Cash (BCH) transactions into their applications. Leveraging modern Swift features, Opal Base offers a robust, efficient, and secure solution for handling BCH transactions. It also stays true to the vision of Satoshi Nakamoto's original white paper on a peer-to-peer electronic cash system. Opal Base supports the BIP-39 standard for mnemonic seed address generation and integrates the powerful SwiftFulcrum framework, providing advanced capabilities for interacting with the Bitcoin Cash network.

## Features

- **Cross-Platform Support**: Ready for iOS, iPadOS, macOS, watchOS, and visionOS apps.
- **BIP‑39 Wallets**: Generate and restore wallets from mnemonic phrases.
- **SwiftFulcrum Integration**: `async`/`await` APIs for live blockchain data, broadcasts, and subscriptions.
- **Balance Caching**: Quickly read cached balances and update them on demand.
- **Transaction & UTXO Management**: Create transactions, select UTXOs, and refresh sets as needed.
- **Transaction History**: Fetch simple or detailed transaction lists for any address.
- **Open Source**: Community driven and open to contributions.

## Installation

### Swift Package Manager

Add Opal Base as a dependency in Xcode or by editing your `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "YourApp",
    dependencies: [
        .package(url: "https://github.com/58opals/OpalBase.git", from: "0.2.0")
    ],
    targets: [
        .target(
            name: "YourApp",
            dependencies: [
                .product(name: "OpalBase", package: "OpalBase")
            ])
    ]
)
```

## Getting started

The snippets below run inside an async context such as `Task` or `@main struct` with `await` support.

### 1. Create a mnemonic, wallet, and account

```swift
import OpalBase

let mnemonic = try Mnemonic(length: .long)
let wallet = Wallet(mnemonic: mnemonic)
try await wallet.addAccount(unhardenedIndex: 0)
let account = try wallet.getAccount(unhardenedIndex: 0)
let service = account.fulcrumService
try await account.addressBook.refreshBalances(using: service)
let history = try await account.addressBook.fetchDetailedTransactions(for: .receiving, using: service)
```

### Generating and Using an Address in the Account

After creating an account, you can generate and use an address for transactions.

```swift
let nextReceivingAddress = try await account.addressBook.getNextEntry(for: .receiving).address
print("Next receiving address: \(nextReceivingAddress)")
```

### Checking Balance from Cache or Blockchain

To check the balance of an account, you can use the cached balance or update it from the blockchain.

```swift
let cachedBalance = try await account.getBalanceFromCache()
print("Cached account balance: \(cachedBalance)")

let blockchainBalance = try await account.calculateBalance()
print("Blockchain account balance: \(blockchainBalance)")
```

### Creating a New Transaction

Here's a quick example to create and send a BCH transaction:

```swift
let recipientAddress = try Address("qrtlrv292x9dz5a24wg6a2a7pntu8am7hyyjjwy0hk")
let transactionHash = try await account.send(
    [
        (value: .init(565), recipientAddress: recipientAddress)
    ]
)
print("Transaction successfully sent with hash: \(transactionHash)")
```

### Fetching Transaction History

Retrieve detailed transaction information for your receiving addresses:

```swift
let service = account.fulcrumService
let history = try await account.addressBook.fetchDetailedTransactions(
    for: .receiving,
    using: service
)
print("Found \(history.count) transactions")
```

### Updating Address Usage Status

```swift
let service = account.fulcrumService
try await account.addressBook.updateAddressUsageStatus(using: service)
```

### Refreshing UTXO Set

To refresh the UTXO set for an account:

```swift
let service = account.fulcrumService
try await account.addressBook.refreshUTXOSet(service: service)
```
### Monitoring Balance Updates

Receive live account balance updates by observing the monitoring stream:

```swift
let updates = try await account.monitorBalances()
for try await balance in updates {
    print("Latest balance: \(balance)")
}
```

Events cover new addresses, UTXO set refreshes, history changes, confirmation updates, and fatal failures. Stop the monitor when leaving scope with `await monitor.stop()` or automatically on deallocation.

## Persisting state

Generate and later restore a wallet snapshot to persist address indexes, cached balances, and transaction history:

```swift
let snapshot = await wallet.makeSnapshot()
// Store `snapshot` with your persistence layer

// Restoring later
let restoredWallet = try await Wallet(from: snapshot)
```

`Wallet.applySnapshot(_:)` can merge a snapshot back into an existing actor instance when the mnemonic and derivation path match.

## Contributing

Issues and pull requests are welcome. Please open a discussion for large-scale proposals so we can align on direction before coding.

## License

Opal Base is available under the MIT license.
