# Opal Base

Status: Developer Preview. The current release line is `v0.4.1`; the public `develop` branch remains the builder-review surface between SemVer tags.

Cash Code v1 is an unreleased Opal-owned candidate with an implemented reference path and open production-readiness gates. It is not included in `v0.4.1` or presented as a Bitcoin Cash ecosystem standard. See [Cash Code v1 Readiness](docs/cash-code-readiness.md).

Opal Base is a Swift package for building Bitcoin Cash wallet and transaction flows on Apple platforms. It gives BCH builders a curated app-facing layer for wallet/account orchestration, CashAddr receive-address reservation, Fulcrum-backed public-chain sync, BCH spend planning, transaction review boundaries, snapshot persistence, CashTokens metadata, CashFusion preparation, and redacted diagnostics.

Mosaic remains an unreleased, macOS-only internal wallet-host alpha for the explicit Opal-v0/chipnet and frozen mainnet-alpha.4/mainnet profiles. Package tests cover synthetic contracts, not live Mosaic support, application durability, or privacy readiness. See the [architecture guide](docs/architecture.md#builder-integration-lanes) for ownership and recovery obligations and the [public API guide](docs/public-api.md) for the integration boundary.

## Why Builders Use It

- Build Bitcoin Cash wallet flows without wiring raw key derivation, address tracking, UTXO refresh, transaction history, and Fulcrum transport by hand.
- Keep secret-bearing wallet authority separate from descriptor-backed public-chain sync, receive-address reservation, external signing review, broadcast, and diagnostics.
- Compose higher-level BCH features through Swift facades under `OpalBase.*` while lower-level packages keep their responsibilities: `OpalCrypto`, `SwiftFulcrum`, `OpalFusion`, and `OpalDiagnostics`.
- Point reviewers to runnable public API examples in `Tests/OpalBaseLocalTests/PublicAPISmokeValidator.swift` and opt-in live Fulcrum examples in `Tests/OpalBaseNetworkTests/NetworkLiveSmokeValidator.swift`.

## Ordinary BCH product

The unreleased `OpalBaseCore` product supports ordinary BCH integration without linking the experimental privacy engines. The existing `OpalBase` product preserves its compatibility import and macOS integrations. See [Durable BCH integration](docs/durable-bch.md) for unsigned review, immutable finalization, atomic first-submission handoff and confirmed-history address bounds.

## Trust Boundaries

- Secret-bearing authority stays in `OpalBase.Wallet`, `OpalBase.Account`, `WalletSecretAccessInteractor`, and `WalletTransactionAuthoringInteractor(privateAccount:)`.
- Public-chain sync can run from `WalletAccountPublicDescriptor`, `WalletTransportInteractor`, and `WalletBlockchainSyncInteractor` without mnemonic, Keychain, Secure Enclave, or root private account authority.
- Receive-address reservation is intentionally separate from generic sync because handing out a CashAddr receive address mutates reservation/cache state.
- External review flows use `WalletTransactionAuthoringInteractor.prepareSpendForExternalReview` and `WalletUnsignedSpendPlan` to reserve UTXOs and change, carry unsigned Bitcoin Cash transaction material, and leave signing, verification policy, and relay to app-owned boundaries.
- Diagnostics are redacted through `OpalDiagnostics`; application logs should not add mnemonics, private keys, passphrases, raw recovery payloads, or unsigned/signed transaction review payloads.

See [Trust Boundaries](docs/trust-boundaries.md) for the full integration model.

The [peer catalog snapshot](docs/peer-catalogs.md) records Base's distinct default URLs, source digest and provider-trust limits, and links SwiftFulcrum's authoritative qualification contract. Catalog inclusion is not live qualification.

## Requirements

- Swift tools version: `6.4`
- Platforms: `macOS 27`, `iOS 27`, `watchOS 27`, `tvOS 27`, `visionOS 27`
- Xcode's Metal Toolchain component, required by the `OpalCrypto` Metal verification target. If it is not installed, run `xcodebuild -downloadComponent MetalToolchain`.

Use the Xcode 27 family with a compiler supporting Swift tools 6.4 and Swift 6 language mode. The supported platform versions above are 27.0 deployment minimums; a newer selected 27.x SDK does not raise them. Before validation, record the active developer-directory selection and overrides, Xcode build, effective Swift compiler and each selected SDK version/path. Record the Metal compiler version and tool paths separately. After any of these inputs changes, use a new external scratch or derived-data lane and rerun the affected builds and tests against the existing dependency lock. Preserve earlier receipts and keep normal signing, security and plugin settings; selecting newer tools neither updates package pins nor renews earlier validation.

## Installation

For reproducible review of the current Swift 6.4 / OS 27 stack, pin an inspected public `develop` revision. Replace the placeholder below with the full commit hash of the reviewed published candidate. The current integration includes the two-account CashToken transfer and reviewed-genesis APIs in the [public API guide](docs/public-api.md#two-account-cashtoken-transfers).

```swift
dependencies: [
    .package(url: "https://github.com/58opals/OpalBase.git", revision: "<reviewed-public-develop-commit>")
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

The current [Package.swift](Package.swift) pins `SwiftFulcrum`, `OpalCrypto`, `OpalFusion`, and `OpalDiagnostics` to exact public integration revisions. Use those declarations when selecting direct requirements on the same packages, including Diagnostics, so the application resolves one compatible graph. Retain the consuming application's `Package.resolved` to record the complete resolved graph. This is an integration snapshot, not a SemVer release.

The published `v0.4.1` tag is **not usable as a SwiftPM version-based dependency** (`from: "0.4.1"` or `exact: "0.4.1"`): SwiftPM rejects its branch-based sibling requirements. Its own `Package.resolved` does not remove that restriction. A future version-consumable release needs a compatible stable dependency graph and an actual consumer-resolution check. See [Release Readiness](docs/release-readiness.md) for the known limitation and gates.

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
- Internal Mosaic wallet reservation, session ownership, journal recovery, and guarded chain reconciliation on macOS; application durability and live-operation gates remain open. See [Architecture](docs/architecture.md#builder-integration-lanes).
- Snapshot persistence, Secure Enclave-backed mnemonic persistence helpers, and redacted diagnostics surfaces.

## Validation

Tests own wallet orchestration, precise amounts, spend reservations, persistence contracts, and adaptation of dependency results. Keep exhaustive primitive and wire-format coverage in its owning dependency, while retaining Base-specific authority, error translation, cancellation, and integration checks. Use small local fixtures when production account capacity is not the behavior under test.

Use the focused development lane for routine feedback and select the owning suite when changing a feature:

```bash
scripts/validate.sh
scripts/validate.sh focused SpendPlanBroadcastValidator
scripts/validate.sh assurance
```

The default `develop` lane runs the public API, durable BCH and wallet security-profile contracts. It is a subset, not complete package assurance. `focused` accepts a literal substring of a discovered test identifier, rejects empty/no-match selections and reports selected/total definitions. Add leading `--list` to inspect any lane without executing tests. `assurance` keeps the complete offline suite, including the unchanged conditional cases. Live and extended live Fulcrum gates are disabled by these entrypoints; live validation remains separately opt-in below.

Discovery compiles the test products once with the tracked `Package.resolved`; execution reuses those products in the same invocation. There is no separate `swift build` prerequisite. SwiftPM still checks incremental inputs on the next invocation, and the script rejects lock changes. The dependency-resolution CI job separately resolves the published graph and checks the lock on pushes and pull requests.

Build products default to `.build/validation`. Set absolute `OPAL_VALIDATION_SCRATCH_PATH` to choose another lane, especially a fresh directory after toolchain changes. Do not reuse a prior `--skip-build` command independently after source, dependency or toolchain changes. Before publication or release, run the applicable full assurance and platform checks in [Release Readiness](docs/release-readiness.md); a focused pass does not replace them.

Live Fulcrum smoke tests are opt-in and run outside these offline lanes:

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
