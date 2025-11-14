![Swift 6.2](https://img.shields.io/badge/swift-6.2-orange)
![SPM](https://img.shields.io/badge/Package%20Manager-SPM-informational)
![Platforms](https://img.shields.io/badge/platforms-iOS%20|%20macOS%20|%20watchOS%20|%20tvOS%20|%20visionOS-blue)

# Opal Base

## Overview

Opal Base is a Swift package that assembles everything you need to build modern Bitcoin Cash (BCH) experiences on Apple platforms. The package ships with actor-based wallet and account models, an address book that automates derivation, coin selection, and caching, a rich transaction toolchain, and battle-tested Fulcrum (ElectrumX) networking built on top of [SwiftFulcrum](https://github.com/58opals/SwiftFulcrum). The library is designed with Swift concurrency from the ground up, making it straightforward to integrate in SwiftUI, SwiftData, or server-side Swift applications.

## Highlights

- **Actor-isolated wallet core** – `Wallet` and `Account` actors wrap BIP-39/BIP-44 derivation, privacy shaping, and address management so mutation is always serialized.
- **Deterministic address book with caching** – Track receiving and change paths, refresh balances through pluggable loaders, and persist cached values for offline reads.
- **Flexible spend planning** – Assemble transactions with `Account.Payment`, privacy-aware coin selection, configurable fee policies, and reservation-aware `SpendPlan` builders.
- **First-class Fulcrum integration** – Async Fulcrum client, address reader, transaction handler, and header reader make it easy to refresh balances, history, and confirmations or broadcast transactions.
- **Streaming monitors & snapshots** – Subscribe to address, UTXO, and confirmation updates or persist actor state with `Wallet.Snapshot` for restoration.

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
let account = try await wallet.fetchAccount(at: 0)
```

### 2. Connect to Fulcrum services

```swift
let configuration = Network.Configuration(
    serverURLs: [URL(string: "wss://fulcrum.example.org:50002")!]
)
let client = try await Network.FulcrumClient(configuration: configuration)
let addressReader = Network.FulcrumAddressReader(client: client)
let transactionHandler = Network.FulcrumTransactionHandler(client: client)
let blockHeaderReader = Network.FulcrumBlockHeaderReader(client: client)
let fulcrum = Wallet.FulcrumAddress(addressReader: addressReader,
                                    transactionHandler: transactionHandler)
```

### 3. Refresh balances and transaction history

```swift
let cached = try await account.loadBalanceFromCache()
print("Cached BCH balance: \(cached.bch)")

let refresh = try await fulcrum.refreshBalances(for: account, usage: .receiving)
print("Latest BCH balance: \(refresh.total.bch)")

let historyChangeSet = try await fulcrum.refreshTransactionHistory(for: account)
print("Fetched \(historyChangeSet.updated.count) history entries")
```

## Managing balances and history

- `Account.loadBalanceFromCache()` reads the aggregated cached amount without making a network call.
- `Account.refreshBalances(for:loader:)` lets you plug in any async loader, while `Wallet.FulcrumAddress.refreshBalances` handles Fulcrum wiring.
- Use `Account.refreshTransactionHistory(using:includeUnconfirmed:)` (or the Fulcrum helper) to keep cached history synchronized, and `Account.refreshTransactionConfirmations` to poll confirmations on demand.
- `Account.loadTransactionHistory()` returns the current cached list of history records for quick display.

## Planning and broadcasting payments

```swift
let recipient = Account.Payment.Recipient(
    address: try Address("bitcoincash:qr..."),
    amount: try Satoshi(5_000)
)
let payment = Account.Payment(
    recipients: [recipient],
    feeContext: .init(networkConditions: .init(fallbackRate: 1_000))
)

let spendPlan = try await account.prepareSpend(payment)
let (hash, result) = try await spendPlan.buildAndBroadcast(via: transactionHandler)
print("Broadcast \(hash.reverseOrder.hexadecimalString) with fee \(result.fee.uint64) satoshis")
```

- Customize fee policy defaults with `Wallet.FeePolicy` or pass an override in `Account.Payment`.
- Inspect `SpendPlan.TransactionResult` for the signed transaction, applied fee, and any change output metadata.
- Call `spendPlan.completeReservation()` or `spendPlan.cancelReservation()` when coordinating with external broadcast flows.

## Streaming updates

`Wallet.FulcrumAddress.Monitor` keeps accounts synchronized by combining address subscriptions and block header updates.

```swift
let monitor = fulcrum.makeMonitor(for: account,
                                  blockHeaderReader: blockHeaderReader)
await monitor.start()

Task.detached {
    for await event in monitor.observeEvents() {
        switch event {
        case .utxosUpdated(let address, let balance, _):
            print("Updated \(address.string) to \(balance.uint64) satoshis")
        case .encounteredFailure(let failure):
            print("Monitor error: \(failure.message)")
        default:
            break
        }
    }
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
