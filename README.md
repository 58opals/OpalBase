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

To integrate Opal Base into your Xcode project using Swift Package Manager, add it to your project's package dependencies by including the following URL:

```swift
https://github.com/58opals/OpalBase.git
```

Follow the on-screen instructions to add the package to your project.

## Usage

To get started with Opal Base, import the library into your Swift file:

```swift
import OpalBase
```

### Creating a New Wallet with BIP-39 Mnemonic Seed

This example demonstrates how to generate a new wallet using a BIP-39 mnemonic seed, providing an easy and secure way for users to manage their BCH transactions.

```swift
let mnemonic = try Mnemonic(words: [
    "kitchen", "stadium", "depth", "camp", "opera", "keen", "power", "cinnamon", "unfair", "west", "panda", "popular", "source", "category", "truth", "dial", "panel", "garden", "above", "top", "glue", "kidney", "effort", "rubber"
])
let wallet = Wallet(mnemonic: mnemonic)
try await wallet.addAccount(unhardenedIndex: 0)
let account = try wallet.getAccount(unhardenedIndex: 0)
let fulcrum = try await account.fulcrumPool.getFulcrum()
try await account.addressBook.refreshBalances(using: fulcrum)
let history = try await account.addressBook.fetchDetailedTransactions(for: .receiving, using: fulcrum)
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
let fulcrum = try await account.fulcrumPool.getFulcrum()
let history = try await account.addressBook.fetchDetailedTransactions(
    for: .receiving,
    using: fulcrum
)
print("Found \(history.count) transactions")
```

### Updating Address Usage Status

```swift
let fulcrum = try await account.fulcrumPool.getFulcrum()
try await account.addressBook.updateAddressUsageStatus(using: fulcrum)
```

### Refreshing UTXO Set

To refresh the UTXO set for an account:

```swift
let fulcrum = try await account.fulcrumPool.getFulcrum()
try await account.addressBook.refreshUTXOSet(fulcrum: fulcrum)
```
### Monitoring Balance Updates

Receive live account balance updates by observing the monitoring stream:

```swift
let updates = try await account.monitorBalances()
for try await balance in updates {
    print("Latest balance: \(balance)")
}
```

## Contributing

We welcome contributions from everyone who aims to enhance and expand the capabilities of Opal Base. Here's how you can contribute:
- Reporting Bugs: Submit an issue to report any bugs or propose feature enhancements.
- Submitting Pull Requests: If you've fixed a bug or added a new feature, submit a pull request for review.
- Documentation: Help improve our documentation, from typos to additional content that makes Opal Base more accessible.

## License

Opal Base is released under the MIT License.

## Acknowledgements

This project is inspired by the vision of Satoshi Nakamoto and the dedication of the Bitcoin Cash community. Special thanks to everyone who contributes to making Opal Base robust and reliable for developers and users alike.

We hope Opal Base accelerates your development process and helps you integrate Bitcoin Cash transactions into your applications effortlessly. For more information, support, or to contribute, please visit our GitHub repository.
