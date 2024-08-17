# Opal Base

## Introduction

**Opal Base** is a cutting-edge, open-source Swift library designed to empower developers within the Apple ecosystem to seamlessly integrate Bitcoin Cash (BCH) transactions into their applications. Leveraging modern Swift features, Opal Base offers a robust, efficient, and secure solution for handling BCH transactions, staying true to the vision of Satoshi Nakamoto's original white paper on a peer-to-peer electronic cash system. Opal Base supports the BIP-39 standard for mnemonic seed address generation and integrates the powerful SwiftFulcrum framework, providing advanced capabilities for interacting with the Bitcoin Cash network.

## Features

- **Seamless Integration**: Easy to incorporate into any iOS, iPadOS, macOS, watchOS, and visionOS project.
- **Modern Swift Practices**: Utilizes the latest in Swift technology, including Protocols, Generics, Concurrency (async/await), and Error Handling.
- **Advanced Network Interaction**: Integrates SwiftFulcrum to interact with the Bitcoin Cash network, enabling real-time transaction monitoring and balance updates.
- **Efficient Transactions**: Optimized for fast, cheap, and reliable peer-to-peer transactions, embracing the core advantages of Bitcoin Cash.
- **Security First**: Built with the highest security standards to ensure safe and secure transactions for users. Includes BIP-39 standard support for mnemonic seed address generation, enabling users to recover their wallets with a human-readable phrase in any other wallet.
- **Open Source**: Encourages community collaboration and improvement, fully available for review and contributions.

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
```

### Generating and Using an Address in the Account

After creating an account, you can generate and use an address for transactions.

```swift
let nextReceivingAddress = try await account.addressBook.getNextEntry(for: .receiving).address
print("Next receiving address: \(nextReceivingAddress)")
```

### Checking Balance

To check the balance of an account:

```swift
let balance = try await account.calculateBalance()
print("Account balance: \(balance)")
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
