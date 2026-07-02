# Opal Base Architecture

## Role

Opal Base is the Bitcoin Cash application-layer foundation in the Opal package stack for Apple platforms. It owns the reusable wallet and account domain behavior that apps need after cryptography and Fulcrum transport are abstracted into lower-level packages.

Consumers use Opal Base when they need wallet flows, CashAddr management, spend planning, snapshotting, and token-aware orchestration rather than raw key or socket primitives. See the [Public API Guide](public-api.md) for the intended workflow entry points and lane-explicit interactor surfaces.

## Upstream Boundaries

- `OpalCrypto` provides the cryptography, seed and key derivation primitives, and signing support consumed by wallet, account, and transaction flows in this package.
- `SwiftFulcrum` provides the underlying Fulcrum protocol transport used by `OpalBase.Network.Fulcrum.Client` and the readers and clients layered on top of it.
- `OpalFusion` provides the native CashFusion runtime and protocol behavior consumed by wallet-backed CashFusion flows in this package.
- `OpalHedge` provides the AnyHedge contract primitives and protocol behavior consumed by wallet-backed hedge funding flows in this package.
- `OpalDiagnostics` provides the shared diagnostics vocabulary, redacted record model, and presentation helpers consumed by Opal Base observability surfaces.
- Opal Base owns the app-facing orchestration above those packages: wallet state, address tracking, spend planning, CashFusion reservation and session preparation, history refresh, snapshotting, storage, and token metadata handling.

## Downstream Integration

- Primary downstream consumers are Opal Wallet and other Swift/BCH apps on Apple platforms.
- A typical integration starts with `OpalBase.Wallet` for management and secret-backed account creation, then exposes narrower composition lanes such as `WalletBlockchainSyncInteractor`, `WalletReceiveAddressInteractor`, `WalletTransactionAuthoringInteractor`, `WalletBroadcastInteractor`, `WalletSecretAccessInteractor`, and `WalletSnapshotInteractor`.
- Descriptor-backed integrations can construct `OpalBase.WalletAccountPublicDescriptor` from a serialized account extended public key plus `OpalBase.Account.Snapshot`, then run public-chain sync without mnemonic, Keychain, Secure Enclave, or root private account authority.
- The package keeps app code focused on wallet workflows instead of re-implementing address books, reservation logic, UTXO caching, transaction history sync, or token metadata plumbing.

## Trust-Domain Lanes

- `WalletSnapshotInteractor` is the storage/import-export snapshot lane. It accepts `OpalBase.Storage.SnapshotPersistence` or `OpalBase.Storage`, moves `OpalBase.Wallet.Snapshot` values, and does not own transport clients, mnemonics, raw transactions, or signing keys.
- `WalletBlockchainSyncInteractor` is the descriptor-backed public-chain sync lane. Its primary constructor takes `WalletAccountPublicDescriptor` and `WalletPublicChainOperations`, so balances, history, UTXOs, and confirmation freshness can run from account public data.
- `WalletTransportInteractor` is the public-chain transport lane. It wraps `Network.AddressReader`, `Network.TransactionClient`, optional `Network.TransactionReader`, optional `Network.BlockHeaderReader`, or a `Network.Fulcrum.Client`; it does not own wallet snapshots or secrets.
- `WalletReceiveAddressInteractor` is the receive derivation and reservation lane. Reservation is intentionally separate from generic sync because handing out a receive address mutates reservation/cache state.
- `WalletSecurityProfile` is the app posture lane for secret persistence, network access, and signing review boundaries. The offline savings signer profile requires Secure Enclave-backed secret persistence, no public-chain networking, and external transaction review.
- `WalletSecretAccessInteractor` is the mnemonic and secure persistence lane. It is the explicit surface for `Storage.PersistenceSession` restore/save/wipe flows, including Keychain and Secure Enclave-backed providers.
- `WalletUnsignedSpendPlan` is the reserved external-review spend lane. It carries an unsigned transaction envelope and reservation lifecycle without retaining private-key material.
- `WalletUnsignedTransactionEnvelope` is the external signing boundary scaffold. It carries an unsigned Bitcoin Cash transaction, the transaction outputs being spent, and the requested signature format without owning QR transport, UI review, script verification, cryptographic signature verification, or broadcast behavior.
- `WalletTransactionAuthoringInteractor` is the user-triggered money-movement lane. Its constructor label is `privateAccount` and it prepares BCH spends, token spends, token genesis, token minting, token commitment mutation, hedge funding, and signing-capable plans.
- `WalletBroadcastInteractor` is the relay and targeted aftermath lane. It owns a `Network.TransactionClient` and updates confirmations for explicitly supplied transaction hashes instead of implying a whole-wallet rebuild.
- `WalletManagementInteractor` is the broad wallet management lane for account creation, account lookup, account count, and snapshot composition around an existing `OpalBase.Wallet`.
- `WalletAssetInteractor` is the token holdings and metadata lane. Token mint authoring remains explicit through the `privateAccount` initializer and otherwise inventory/metadata operations can stay read-oriented.
- `CashFusionInteractor` is the CashFusion session lifecycle lane on macOS. It requires `privateAccount` because coordinator session preparation signs and reserves wallet-owned inputs.
- `ClaimableInteractor` is the claimable contract lane for drafts, funding outputs, envelopes, status resolution, claim/refund transaction building, and recovery material without turning Claimable into a wallet/account backdoor.
- `WalletObservabilityInteractor` is the diagnostics lane. It only reads redacted `OpalDiagnostics.Record` values; event recording stays in the domain operations so sensitive payloads are not accepted through a generic logging facade.

## Owned Capabilities

- Actor-isolated wallet and account surfaces through `OpalBase.Wallet` and `OpalBase.Account`, with lane-explicit public interactors for Wallet composition.
- Scoped secp256k1 signing through `OpalBase.Key.SigningKey`, which derives public keys and signs without exposing raw private-key export as part of the preferred signing path.
- Deterministic address management and gap-limit-aware address-book behavior for BCH receiving and change flows.
- BCH spend planning, transaction construction, signing, broadcast helpers, and confirmation or history refresh flows, split between authoring, broadcast, and public-chain sync lanes.
- Security posture scaffolding for Lockdown Mode-compatible app layers through `WalletSecurityProfile.offlineSavingsSigner`, `WalletTransactionAuthoringInteractor.prepareSpendForExternalReview`, and external signing review data contracts.
- Wallet-backed CashFusion pilot orchestration over `OpalFusion.Client.Session` for explicitly selected wallet UTXOs and fresh wallet-owned receiving outputs, with OpalFusion host callbacks hidden behind OpalBase CashFusion operation surfaces.
- Snapshotting and restoration of wallet, account, and token metadata state.
- Storage helpers, including Secure Enclave-backed mnemonic protection through `OpalBase.Storage.Security.makeSecureEnclaveBacked`.
- CashTokens and BCMR metadata support through `OpalBase.CashTokens.*`.
- Fulcrum-facing orchestration and monitoring through `OpalBase.Network.Fulcrum.Client`, `OpalBase.Wallet.Fulcrum`, and `OpalBase.WalletTransportInteractor`.

## Non-Goals

- UI, app-shell, or end-user product UX ownership.
- Raw cryptography or numeric primitives that belong in `OpalCrypto`.
- Raw network transport or protocol wiring that belong in `SwiftFulcrum`; `Network.Fulcrum` remains public-chain oriented and must not own wallet secrets or SwiftData snapshots.
- Native CashFusion protocol runtime that belongs in `OpalFusion`.
- AnyHedge contract primitives or protocol behavior that belong in `OpalHedge`.
- Cross-package diagnostics infrastructure that belongs in `OpalDiagnostics`.
- Broad wallet/account authority as the only public integration surface. New app code should prefer the lane-specific interactors when composing Wallet features.
- Multi-chain scope. This package is Bitcoin Cash-specific.
- Weekly reporting, portfolio prioritization, dependency drift snapshots, or operational workflow policy.

## Integration Pointers

- Start with the quick start in the root README and the [Public API Guide](public-api.md), then layer in live Fulcrum connectivity with `OpalBase.Network.Fulcrum.Client` and `OpalBase.Wallet.Fulcrum`.
- See `Tests/OpalBaseLocalTests/PublicAPISmokeValidator.swift` for public-surface composition across wallet, network, storage, block, and token metadata APIs.
- See `Tests/OpalBaseNetworkTests/NetworkLiveSmokeValidator.swift` for a minimal live-network example using `OPAL_FULCRUM_URL` and `OPAL_RUN_LIVE_NETWORK_TESTS`.
- Use `swift test` for package validation. Network tests remain opt-in through environment variables.

## Current Direction

Near-term work should keep the app-layer contract clear, examples legible, and downstream integration expectations stable for Apple-platform Bitcoin Cash apps.
