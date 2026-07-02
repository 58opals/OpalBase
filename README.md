# Opal Base

Status: Developer Preview on develop

Opal Base is a Swift package for building Bitcoin Cash wallet and transaction flows on Apple platforms. It combines actor-isolated wallet and account models, deterministic address management, transaction building and signing, Fulcrum-backed network access, snapshot persistence, and CashTokens metadata support behind a concurrency-first API.

## Who It's For

Use Opal Base if you're building an Apple-platform app or service that needs BCH wallet derivation, address tracking, transaction creation, or Fulcrum-backed sync without stitching those surfaces together yourself.

## Role in the BCH Stack

- Opal Base owns the app-facing Bitcoin Cash wallet and account domain layer for Apple-platform consumers.
- It composes lower-level Opal packages: `OpalCrypto` for cryptography and signing primitives, `SwiftFulcrum` for Fulcrum transport, `OpalFusion` for CashFusion protocol runtime, `OpalHedge` for AnyHedge primitives, and `OpalDiagnostics` for redacted diagnostics vocabulary.
- Downstream consumers include Opal Wallet and other Swift/BCH apps that need reusable wallet, storage, and network orchestration.
- For package boundaries and integration notes, see [Architecture](docs/architecture.md) and the [Public API Guide](docs/public-api.md).

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

If you need unreleased APIs, depend on the `develop` branch or a specific revision instead of a release tag.

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
let firstReceivingAddress = try await account.reserveNextReceivingDerivedAddress()

print(firstReceivingAddress.address.string)
```

This gives you a wallet, the first account, and the first derived receiving address. From there you can attach `OpalBase.Network.Fulcrum.Client` and `OpalBase.Wallet.Fulcrum` to refresh balances, history, and confirmations against live BCH infrastructure.

## Key Capabilities

- Actor-isolated wallet and account models for BIP-39 and BIP-44 style derivation and serialized mutation.
- Deterministic address book support for CashAddr receiving and change address tracking, balance refresh, and transaction history caching.
- Spend planning, transaction building, and broadcast helpers for BCH payments and token-aware flows.
- Wallet-backed CashFusion pilot orchestration over `OpalFusion.Client.Session` for explicitly selected wallet UTXOs and fresh wallet-owned receiving outputs from caller-provided amounts, currently limited to the P2PKH-only live path.
- Fulcrum-facing orchestration for address, transaction, header, and monitoring workflows.
- Snapshot persistence, storage helpers, and CashTokens metadata / BCMR support.

## Boundaries

- Opal Base is not a UI or app-shell package.
- Raw cryptography, key primitives, and signing infrastructure remain the responsibility of `OpalCrypto`.
- Raw Fulcrum transport and low-level network protocol concerns remain the responsibility of `SwiftFulcrum`.
- CashFusion coordinator protocol behavior remains the responsibility of `OpalFusion`.
- AnyHedge contract primitives and protocol behavior remain the responsibility of `OpalHedge`.
- Shared diagnostics categories, events, records, and presentation helpers remain the responsibility of `OpalDiagnostics`.
- Portfolio governance, weekly reporting, and repository operations policy stay outside this package repository.

## Secure Enclave Storage

If you need fail-closed mnemonic persistence on Apple hardware, opt into the Secure Enclave-backed storage security factory and require Secure Enclave during save:

```swift
let storage = try OpalBase.Storage.makeSecureEnclaveBacked(
    valueClient: yourValueClient
)

let protectionMode = try await storage.persistState(
    for: wallet,
    policy: .requireSecureEnclave
)

assert(protectionMode == .secureEnclave)
```

This protects the persisted mnemonic + passphrase at rest with a device-bound Secure Enclave key and user-presence gating. It does not move BCH signing into the Secure Enclave; once a wallet is restored, secp256k1 signing still happens through OpalCrypto in process memory.

Apps that build a Lockdown Mode-compatible offline Bitcoin Cash savings signer can also use `OpalBase.WalletSecurityProfile.offlineSavingsSigner` with `WalletSecretAccessInteractor` to make the strict secret-storage posture explicit at the call site.

For scoped in-process signing, prefer `OpalBase.Key.SigningKey` after importing raw secp256k1 private-key bytes. It derives public keys and signs without exposing a public raw-byte export API; raw `Data` private-key APIs remain explicit compatibility, WIF/export, recovery, or wire-format surfaces.

For spending from that posture, use `WalletTransactionAuthoringInteractor.prepareSpendForExternalReview` to get a `WalletUnsignedSpendPlan` rather than building a signed transaction in process. The unsigned plan reserves the selected UTXOs and change address, carries the unsigned Bitcoin Cash transaction plus the transaction outputs being spent, and leaves relay to a separate online component after external signing is complete.

## Validation

Command:

```bash
swift test
```

Result: Passed on 2026-06-19: 796 tests in 88 suites passed after 128.553 seconds.

## License

Opal Base is available under the [Apache License 2.0](LICENSE). Copyright 2026 58 Opals.

## More Examples

- [Public API smoke test](Tests/OpalBaseLocalTests/PublicAPISmokeValidator.swift)
- [Public API guide](docs/public-api.md)
- [Network live smoke test](Tests/OpalBaseNetworkTests/NetworkLiveSmokeValidator.swift)
- [Architecture and integration notes](docs/architecture.md)
