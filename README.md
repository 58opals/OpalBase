# Opal Base

Status: Developer Preview. The current release line is `v0.4.1`; the public `develop` branch remains the builder-review surface between SemVer tags.

Cash Code v1 is an unreleased Opal-owned candidate with an implemented reference path and open production-readiness gates. It is not included in `v0.4.1` or presented as a Bitcoin Cash ecosystem standard. See [Cash Code v1 Readiness](docs/cash-code-readiness.md).

Opal Base is a Swift package for building Bitcoin Cash wallet and transaction flows on Apple platforms. It gives BCH builders a curated app-facing layer for wallet/account orchestration, CashAddr receive-address reservation, Fulcrum-backed public-chain sync, BCH spend planning, transaction review boundaries, snapshot persistence, CashTokens metadata, CashFusion preparation, and redacted diagnostics.

The internal Mosaic wallet-host alpha remains limited to the explicitly selected Opal-v0/chipnet and frozen mainnet-alpha.4/mainnet pairs. The macOS-only private-alpha facade accepts only the exact `Mosaic/0-opal-mainnet-alpha.4` and `bch-mainnet-p2pkh-schnorr/0-opal-mainnet-alpha.4` identifiers, consumes paired move-only Fusion and Base fresh handles or loaded-recovery handles whose bindings are compared exactly, and binds Fusion's distinct attempt, generation, and material identifiers plus the wallet reservation UUID and wallet generation before wallet mutation. One `MosaicPrivateAlphaRecoveryOwner` replays only authenticated reserve, finalize, commit, and release facts; reconciles approval-gated broadcast, tri-state chain presence, reorganization, disappearance, and finality; and authorizes exact-owner quarantine release and terminal journal cleanup without restoring signer access or creating an in-place retry. Mainnet coverage remains synthetic: the app still owns key protection, atomic durable storage, journal enumeration, cross-process exclusion, rollback and deletion detection, combined terminal storage, finality policy, and physical deletion. Durable missing-input tombstones remain application-owned and absent from the package; without exact authenticated app evidence, an ambiguous locally-signed or commit-intent absence stays quarantined and fails closed. Public session composition, concrete Tor/relay deployment, and live mainnet broadcast evidence also remain absent. The implementation is proved behind private SPI against the tracked public Fusion and Crypto revisions in a clean public-URL lane, but it remains unreleased and must not be presented as live Mosaic support.

## Why Builders Use It

- Build Bitcoin Cash wallet flows without wiring raw key derivation, address tracking, UTXO refresh, transaction history, and Fulcrum transport by hand.
- Keep secret-bearing wallet authority separate from descriptor-backed public-chain sync, receive-address reservation, external signing review, broadcast, and diagnostics.
- Compose higher-level BCH features through Swift facades under `OpalBase.*` while lower-level packages keep their responsibilities: `OpalCrypto`, `SwiftFulcrum`, `OpalFusion`, and `OpalDiagnostics`.
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
- Xcode's Metal Toolchain component, required by the `OpalCrypto` Metal verification target. If it is not installed, run `xcodebuild -downloadComponent MetalToolchain`.

## Installation

For released-package consumers, use the latest tag:

```swift
dependencies: [
    .package(url: "https://github.com/58opals/OpalBase.git", from: "0.4.1")
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

Do not treat the `develop` branch as a SemVer release. The `v0.4.1` release keeps sibling Opal dependencies on public `develop` branches with tracked revisions in `Package.resolved`; moving those dependencies to public SemVer tags is a separate maintainer-approved dependency change.

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
- Evaluating Cash Code maturity: [Cash Code v1 Readiness](docs/cash-code-readiness.md)
- Evaluating release state: [Release Readiness](docs/release-readiness.md)

## Key Capabilities

- Actor-isolated wallet and account models for BIP-39 and BIP-44 style derivation and serialized mutation.
- Deterministic CashAddr receiving and change address tracking, BCH balance refresh, UTXO refresh, transaction history caching, and confirmation refresh.
- Spend planning, transaction construction, external-review unsigned spend plans, in-process signing paths, broadcast helpers, and targeted broadcast aftermath reconciliation.
- Fulcrum-facing public-chain orchestration for address, transaction, header, and monitoring workflows.
- Cash Code v1 candidate identifiers, compressed-P2PKH derivation, durable confirmed and mempool restoration, reorganization rollback, public-only state, opaque-key spending integration, and bounded sender prefix grinding.
- CashTokens vocabulary, BCMR metadata support, token holdings, token genesis, token mint, token spend, and token commitment mutation preparation.
- Wallet-backed CashFusion pilot orchestration on macOS.
- Internal Mosaic reservation for the explicit Opal-v0/chipnet and mainnet-alpha.4/mainnet pairs; distinct Fusion attempt, generation, and material binding plus wallet reservation UUID and generation; authoritative previous-output resolution; contributor signing; complete P2PKH Schnorr verification; AES-GCM-authenticated whole-journal snapshots; replay-only wallet recovery; guarded broadcast and chain reconciliation; exact-owner quarantine release; and terminal cleanup authority on macOS. Durable outer composition and missing-input tombstones remain app-owned and unimplemented, while public session wiring, concrete private transport, and live broadcast proof remain pending or unproved.
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
- [Architecture Complexity Audit](docs/architecture-complexity-audit.md)
- [Cash Code v1 Candidate Profile](docs/cash-code-v1.md)
- [Cash Code v1 Readiness](docs/cash-code-readiness.md)
- [Cash Code v1 Conformance Vectors](docs/cash-code-v1-vectors.json)
- [Cash Code v1 Negative Vectors](docs/cash-code-v1-negative-vectors.json)
- [RPA Compatibility Decision](docs/rpa-compatibility-decision.md)
- [RPA Historical Scan Benchmark Gate](docs/rpa-historical-scan-benchmark-gate.md)
- [Release Readiness](docs/release-readiness.md)
- [Changelog](CHANGELOG.md)
- [Public API smoke test](Tests/OpalBaseLocalTests/PublicAPISmokeValidator.swift)
- [Network live smoke test](Tests/OpalBaseNetworkTests/NetworkLiveSmokeValidator.swift)
