# Opal Base

Status: Developer Preview. The latest released tag is `v0.3.0`; the public `develop` branch is the current builder-review surface for the next release candidate.

Opal Base is a Swift package for building Bitcoin Cash wallet and transaction flows on Apple platforms. It gives BCH builders a curated app-facing layer for wallet/account orchestration, CashAddr receive-address reservation, Fulcrum-backed public-chain sync, BCH spend planning, transaction review boundaries, snapshot persistence, CashTokens metadata, CashFusion preparation, AnyHedge funding preparation, and redacted diagnostics.

## Why Builders Use It

- Build Bitcoin Cash wallet flows without wiring raw key derivation, address tracking, UTXO refresh, transaction history, and Fulcrum transport by hand.
- Keep secret-bearing wallet authority separate from descriptor-backed public-chain sync, receive-address reservation, external signing review, broadcast, and diagnostics.
- Compose higher-level BCH features through Swift facades under `OpalBase.*` while lower-level packages keep their responsibilities: `OpalCrypto`, `SwiftFulcrum`, `OpalFusion`, `OpalHedge`, and `OpalDiagnostics`.
- Point reviewers to runnable public API examples in `Tests/OpalBaseLocalTests/PublicAPISmokeValidator.swift` and opt-in live Fulcrum examples in `Tests/OpalBaseNetworkTests/NetworkLiveSmokeValidator.swift`.

## Trust Boundaries

- Secret-bearing authority stays in `OpalBase.Wallet`, `OpalBase.Account`, `WalletSecretAccessInteractor`, and `WalletTransactionAuthoringInteractor(privateAccount:)`.
- Public-chain sync can run from `WalletAccountPublicDescriptor`, `WalletTransportInteractor`, and `WalletBlockchainSyncInteractor` without mnemonic, Keychain, Secure Enclave, or root private account authority.
- Receive-address reservation is intentionally separate from generic sync because handing out a CashAddr receive address mutates reservation/cache state.
- External review flows use `WalletTransactionAuthoringInteractor.prepareSpendForExternalReview` and `WalletUnsignedSpendPlan` to reserve UTXOs and change, carry unsigned Bitcoin Cash transaction material, and leave signing, verification policy, and relay to app-owned boundaries.
- Diagnostics are redacted through `OpalDiagnostics`; application logs should not add mnemonics, private keys, passphrases, raw recovery payloads, or unsigned/signed transaction review payloads.

See [Trust Boundaries](docs/trust-boundaries.md) for the full integration model.

## Requirements

- Swift tools version: `6.2`
- Platforms: `macOS 26`, `iOS 26`, `watchOS 26`, `tvOS 26`, `visionOS 26`

## Installation

For released-package consumers, use the latest tag:

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

For public review of unreleased APIs, use the public `develop` branch or a specific public revision:

```swift
dependencies: [
    .package(url: "https://github.com/58opals/OpalBase.git", branch: "develop")
]
```

Do not treat the `develop` branch as a SemVer release. A future `v0.4.0` release still needs coordinated dependency hardening and release-readiness validation.

## 5-Minute Quick Start

Run this inside an async context such as `Task {}` or an async entry point:

```swift
import OpalBase

let mnemonic = try OpalBase.Key.Mnemonic.generate(
    length: .words12,
    language: .english
)
let wallet = try OpalBase.Wallet(mnemonic: mnemonic)
let management = OpalBase.WalletManagementInteractor(wallet: wallet)

try await management.addAccount(unhardenedIndex: 0)
let account = try await management.fetchAccount(at: 0)

let receiveAddresses = OpalBase.WalletReceiveAddressInteractor(account: account)
let receiving = try await receiveAddresses.reserveNextReceivingDerivedAddress()

print(receiving.address.string)
```

You now have mnemonic-backed wallet authority, the first BCH account, and a reserved CashAddr receive address. Continue with the [BCH Builder Starter Guide](docs/starter-guide.md) to restore a wallet, construct a public descriptor, connect to Fulcrum, refresh BCH balance/history/UTXOs/confirmations, and prepare a BCH spend for external review.

## Common Builder Paths

- New to the package: [BCH Builder Starter Guide](docs/starter-guide.md)
- Looking up a task: [Recipes](docs/recipes.md)
- Checking secret and signing boundaries: [Trust Boundaries](docs/trust-boundaries.md)
- Reviewing available facades: [Public API Guide](docs/public-api.md)
- Understanding package boundaries: [Architecture](docs/architecture.md)
- Evaluating release state: [Release Readiness](docs/release-readiness.md)

## Key Capabilities

- Actor-isolated wallet and account models for BIP-39 and BIP-44 style derivation and serialized mutation.
- Deterministic CashAddr receiving and change address tracking, BCH balance refresh, UTXO refresh, transaction history caching, and confirmation refresh.
- Spend planning, transaction construction, external-review unsigned spend plans, in-process signing paths, broadcast helpers, and targeted broadcast aftermath reconciliation.
- Fulcrum-facing public-chain orchestration for address, transaction, header, and monitoring workflows.
- CashTokens vocabulary, BCMR metadata support, token holdings, token genesis, token mint, token spend, and token commitment mutation preparation.
- Wallet-backed CashFusion pilot orchestration on macOS and wallet-facing AnyHedge funding preparation.
- Snapshot persistence, Secure Enclave-backed mnemonic persistence helpers, and redacted diagnostics surfaces.

## Validation

Local validation:

```bash
swift build
swift test
```

Live Fulcrum smoke tests are opt-in:

```bash
OPAL_RUN_LIVE_NETWORK_TESTS=1 OPAL_FULCRUM_URL=wss://your.fulcrum.example:50004 swift test --filter NetworkLiveSmokeValidator
```

## License

Opal Base is available under the [Apache License 2.0](LICENSE). Copyright 2026 58 Opals.

## Documentation Map

- [BCH Builder Starter Guide](docs/starter-guide.md)
- [Recipes](docs/recipes.md)
- [Trust Boundaries](docs/trust-boundaries.md)
- [Public API Guide](docs/public-api.md)
- [Architecture](docs/architecture.md)
- [Release Readiness](docs/release-readiness.md)
- [Changelog](CHANGELOG.md)
- [Public API smoke test](Tests/OpalBaseLocalTests/PublicAPISmokeValidator.swift)
- [Network live smoke test](Tests/OpalBaseNetworkTests/NetworkLiveSmokeValidator.swift)
