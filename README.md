# OpalBase

OpalBase is a Swift package for building Bitcoin Cash wallet and transaction flows on Apple platforms. It combines actor-isolated wallet and account models, deterministic address management, transaction building and signing, Fulcrum-backed network access, snapshot persistence, and CashTokens metadata support behind a concurrency-first API.

## Who It's For

Use OpalBase if you're building an Apple-platform app or service that needs BCH wallet derivation, address tracking, transaction creation, or Fulcrum-backed sync without stitching those surfaces together yourself.

## Requirements

- Swift tools version: `6.2`
- Platforms:
  - `macOS 26`
  - `iOS 26`
  - `watchOS 26`
  - `tvOS 26`
  - `visionOS 26`

## Installation

Add `OpalBase` to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/58opals/OpalBase.git", from: "0.3.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "OpalBase", package: "OpalBase")
        ]
    )
]
```

If you need unreleased APIs, depend on the `main` branch or a specific revision instead of a release tag.

## Quick Start

Run this inside an async context such as `Task {}` or an async entry point:

```swift
import OpalBase

let mnemonic = try OpalBase.Key.Mnemonic.generate(
    length: .words12,
    language: .english
)
let wallet = try OpalBase.Wallet(mnemonic: mnemonic)

try await wallet.addAccount(unhardenedIndex: 0)
let account = try await wallet.fetchAccount(at: 0)
let firstReceivingEntry = try await account.selectNextEntry(for: .receiving)

print(firstReceivingEntry.address.string)
```

This gives you a wallet, the first account, and the first derived receiving address. From there you can attach `OpalBase.Network.Fulcrum.Client` and `OpalBase.Wallet.Fulcrum` to refresh balances, history, and confirmations against live BCH infrastructure.

## Key Capabilities

- Actor-isolated wallet and account models for BIP-39 and BIP-44 style derivation and serialized mutation.
- Deterministic address book support for receiving and change address tracking, balance refresh, and transaction history caching.
- Spend planning, transaction building, and broadcast helpers for BCH payments and token-aware flows.
- Fulcrum integration for address, transaction, header, and monitoring workflows.
- Snapshot persistence, storage helpers, and CashTokens metadata / BCMR support.

## Secure Enclave Storage

If you need fail-closed mnemonic persistence on Apple hardware, opt into the Secure Enclave-backed storage security factory and require Secure Enclave during save:

```swift
let security = try OpalBase.Storage.Security.makeSecureEnclaveBacked()
let storage = try OpalBase.Storage(
    valueClient: yourValueClient,
    security: security
)

let protectionMode = try await storage.persistState(
    for: wallet,
    policy: .requireSecureEnclave
)

assert(protectionMode == .secureEnclave)
```

This protects the persisted mnemonic + passphrase at rest with a device-bound Secure Enclave key and user-presence gating. It does not move BCH signing into the Secure Enclave; once a wallet is restored, secp256k1 signing still happens through OpalCrypto in process memory.

## Validation

```bash
swift test
```

## More Examples

- [Public API smoke test](Tests/OpalBaseLocalTests/PublicAPISmokeValidator.swift)
- [Network live smoke test](Tests/OpalBaseNetworkTests/NetworkLiveSmokeValidator.swift)
