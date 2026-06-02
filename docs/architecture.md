# Opal Base Architecture

## Role

Opal Base is the Bitcoin Cash application-layer foundation in the Opal package stack for Apple platforms. It owns the reusable wallet and account domain behavior that apps need after cryptography and Fulcrum transport are abstracted into lower-level packages.

Consumers use Opal Base when they need wallet flows, CashAddr management, spend planning, snapshotting, and token-aware orchestration rather than raw key or socket primitives. See the [Public API Guide](public-api.md) for the intended workflow entry points.

## Upstream Boundaries

- `OpalCrypto` provides the cryptography, seed and key derivation primitives, and signing support consumed by wallet, account, and transaction flows in this package.
- `SwiftFulcrum` provides the underlying Fulcrum protocol transport used by `OpalBase.Network.Fulcrum.Client` and the readers and clients layered on top of it.
- `OpalFusion` provides the native CashFusion runtime and protocol behavior consumed by wallet-backed CashFusion flows in this package.
- Opal Base owns the app-facing orchestration above those packages: wallet state, address tracking, spend planning, CashFusion reservation and session preparation, history refresh, snapshotting, storage, and token metadata handling.

## Downstream Integration

- Primary downstream consumers are Opal Wallet and other Swift/BCH apps on Apple platforms.
- A typical integration starts with `OpalBase.Wallet`, adds or restores an `OpalBase.Account`, derives receiving addresses through account facade types, layers in live network access through `OpalBase.Network.Fulcrum.Client` and `OpalBase.Wallet.Fulcrum`, and persists state through `OpalBase.Storage.PersistenceSession`.
- The package keeps app code focused on wallet workflows instead of re-implementing address books, reservation logic, UTXO caching, transaction history sync, or token metadata plumbing.

## Owned Capabilities

- Actor-isolated wallet and account surfaces through `OpalBase.Wallet` and `OpalBase.Account`.
- Deterministic address management and gap-limit-aware address-book behavior for BCH receiving and change flows.
- BCH spend planning, transaction construction, signing, broadcast helpers, and confirmation or history refresh flows.
- Wallet-backed CashFusion pilot orchestration over `OpalFusion.Client.Session` for explicitly selected wallet UTXOs and fresh wallet-owned receiving outputs.
- Snapshotting and restoration of wallet, account, and token metadata state.
- Storage helpers, including Secure Enclave-backed mnemonic protection through `OpalBase.Storage.Security.makeSecureEnclaveBacked`.
- CashTokens and BCMR metadata support through `OpalBase.CashTokens.*`.
- Fulcrum-facing orchestration and monitoring through `OpalBase.Network.Fulcrum.Client` and `OpalBase.Wallet.Fulcrum`.

## Non-Goals

- UI, app-shell, or end-user product UX ownership.
- Raw cryptography or numeric primitives that belong in `OpalCrypto`.
- Raw network transport or protocol wiring that belong in `SwiftFulcrum`.
- Multi-chain scope. This package is Bitcoin Cash-specific.
- Weekly reporting, portfolio prioritization, dependency drift snapshots, or operational workflow policy.

## Integration Pointers

- Start with the quick start in the root README and the [Public API Guide](public-api.md), then layer in live Fulcrum connectivity with `OpalBase.Network.Fulcrum.Client` and `OpalBase.Wallet.Fulcrum`.
- See `Tests/OpalBaseLocalTests/PublicAPISmokeValidator.swift` for public-surface composition across wallet, network, storage, block, and token metadata APIs.
- See `Tests/OpalBaseNetworkTests/NetworkLiveSmokeValidator.swift` for a minimal live-network example using `OPAL_FULCRUM_URL` and `OPAL_RUN_LIVE_NETWORK_TESTS`.
- Use `swift test` for package validation. Network tests remain opt-in through environment variables.

## Current Direction

Near-term work should keep the app-layer contract clear, examples legible, and downstream integration expectations stable for Apple-platform Bitcoin Cash apps.
