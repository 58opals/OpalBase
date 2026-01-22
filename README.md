![Swift 6.2](https://img.shields.io/badge/swift-6.2-orange)
![SPM](https://img.shields.io/badge/Package%20Manager-SPM-informational)
![Platforms](https://img.shields.io/badge/platforms-iOS%20|%20macOS%20|%20watchOS%20|%20tvOS%20|%20visionOS-blue)

# Opal Base

## Overview

Opal Base is a Swift package that assembles everything you need to build modern Bitcoin Cash (BCH) experiences on Apple platforms.
It ships with actor-based wallet and account models; a deterministic address book that automates derivation, caching, and coin selection; a transaction toolchain for building and signing modern BCH transactions; and battle-tested Fulcrum networking built on top of [SwiftFulcrum](https://github.com/58opals/SwiftFulcrum).
The library is designed with Swift concurrency from the ground up, making it straightforward to integrate in SwiftUI, SwiftData, or server-side Swift applications.

## Highlights

- **Actor-isolated wallet core**: `Wallet` and `Account` actors wrap BIP-39/BIP-44 derivation, address management, and serialized mutation.
- **Deterministic address book with caching**: Track receiving and change paths, scan for used addresses, refresh UTXO sets and history, and read cached values offline.
- **Flexible spend planning**: Assemble transactions with `Account.Payment`, privacy-aware coin selection, configurable fee policies, and reservation-aware `Account.SpendPlan`.
- **First-class Fulcrum integration**: `Network.FulcrumClient` plus readers/handlers for addresses, transactions, block headers, and server/mempool info.
- **Streaming monitors & snapshots**: Monitor address/UTXO/history/confirmation changes via `AsyncThrowingStream`, and persist/restore actor state with `Wallet.Snapshot`.

## Installation

### Swift Package Manager

Add Opal Base as a dependency in Xcode or by editing your `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "YourApp",
    dependencies: [
        .package(url: "https://github.com/58opals/OpalBase.git", from: "0.3.0")
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

> If you're tracking unreleased API changes on `main`, depend on a branch or revision instead of a release tag.

## Getting started

The snippets below run inside an async context such as `Task {}` or an `@main` entry point with `await` support.

### 1. Create a mnemonic, wallet, and account

```swift
import OpalBase

let mnemonic = try Mnemonic(length: .long)
let wallet = Wallet(mnemonic: mnemonic)

try await wallet.addAccount(unhardenedIndex: 0)
let account = try await wallet.fetchAccount(at: 0)
```

### 2. Connect to Fulcrum services

Create a Fulcrum client, then wire up the readers you need.

```swift
import OpalBase

let configuration = Network.Configuration(
    serverURLs: [
        URL(string: "wss://fulcrum.example.org:50002")!
    ],
    network: .mainnet
)

let client = try await Network.FulcrumClient(configuration: configuration)

let addressReader = Network.FulcrumAddressReader(client: client)
let transactionHandler = Network.FulcrumTransactionHandler(client: client)
let blockHeaderReader = Network.FulcrumBlockHeaderReader(client: client)

let fulcrum = Wallet.FulcrumAddress(
    addressReader: addressReader,
    transactionHandler: transactionHandler
)
```

### 3. Refresh balances, UTXOs, and transaction history

```swift
let cached = try await account.loadBalanceFromCache()
print("Cached BCH balance: \(cached.bch)")

let refresh = try await fulcrum.refreshBalances(for: account, usage: .receiving)
print("Latest BCH balance: \(refresh.total.bch)")

let historyChangeSet = try await fulcrum.refreshTransactionHistory(for: account)
print("""
History: +\(historyChangeSet.inserted.count) \
~\(historyChangeSet.updated.count) \
-\(historyChangeSet.removed.count)
""")

let confirmationChangeSet = try await fulcrum.refreshTransactionConfirmations(for: account)
print("Confirmation updates: \(confirmationChangeSet.updated.count)")
```

## Managing balances and history

* `Account.loadBalanceFromCache()` reads the aggregated cached amount without making a network call.
* `Account.refreshBalances(for:loader:)` lets you plug in any async loader, while `Wallet.FulcrumAddress.refreshBalances(for:usage:)` handles Fulcrum wiring and used-address scanning.
* Use `Account.refreshTransactionHistory(using:usage:includeUnconfirmed:)` (or the Fulcrum helper) to keep cached history synchronized.
* Use `Account.refreshTransactionConfirmations(using:)` (or the Fulcrum helper) to poll confirmation heights on demand.
* `Account.loadTransactionHistory()` returns the current cached list of history records for quick display.

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
print("Broadcast \(hash.reverseOrder.hexadecimalString) with fee \(result.fee.uint64) satoshi")
```

* Customize fee policy defaults with `Wallet.FeePolicy` or pass overrides in `Account.Payment`.
* Inspect `Account.SpendPlan.TransactionResult` for the signed transaction, applied fee, and output metadata.
* Call `spendPlan.completeReservation()` or `spendPlan.cancelReservation()` when coordinating with external broadcast flows.

## Streaming updates

`Wallet.FulcrumAddress.Monitor` keeps an `Account` synchronized by combining address subscriptions and block header updates, and exposes events as an `AsyncThrowingStream`.

```swift
let monitor = fulcrum.makeMonitor(for: account, blockHeaderReader: blockHeaderReader)
let events = await monitor.makeEventStream() // auto-starts by default

Task.detached {
    do {
        for try await event in events {
            switch event {
            case .addressTracked(let address):
                print("Tracking \(address.string)")

            case .utxosChanged(let changeSet):
                print("UTXO change for \(changeSet.address.string): \(changeSet.balance.uint64) sat")

            case .historyChanged(let changeSet):
                print("History change: +\(changeSet.inserted.count) ~\(changeSet.updated.count) -\(changeSet.removed.count)")

            case .confirmationsChanged(let changeSet):
                print("Confirmation change: \(changeSet.updated.count) updates")

            case .performedFullRefresh(let utxoRefresh, let historyChangeSet):
                print("Full refresh balance: \(utxoRefresh.totalBalance.uint64) sat")
                print("Full refresh history: +\(historyChangeSet.inserted.count) ~\(historyChangeSet.updated.count) -\(historyChangeSet.removed.count)")

            case .encounteredFailure(let failure):
                print("Monitor failure: \(failure.message)")

            case .terminated(let termination):
                print("Monitor terminated: \(termination.reason)")
            }
        }
    } catch {
        print("Monitor stream ended with error: \(error)")
    }
}
```

Stop the monitor explicitly when you’re done:

```swift
await monitor.stop()
```

## Persisting state

Generate and later restore a wallet snapshot to persist address indexes, cached balances, and transaction history:

```swift
let snapshot = await wallet.makeSnapshot()
// Store `snapshot` with your persistence layer (treat as sensitive).

// Restoring later
let restoredWallet = try await Wallet(from: snapshot)
```

`Wallet.applySnapshot(_:)` can merge a snapshot back into an existing actor instance when the mnemonic and derivation path match.

## Contributing

Issues and pull requests are welcome. Please open a discussion for large-scale proposals so we can align on direction before coding.

## License

Opal Base is available under the MIT license.
