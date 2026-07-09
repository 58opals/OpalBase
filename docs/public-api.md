# Public API Guide

Opal Base exposes a workflow-shaped API under the `OpalBase.*` namespace. Builder-facing integrations should start from the public facades in `Sources/OpalBase/Public` and only drop lower when custom storage, networking, transaction handling, or protocol research requires it.

## How To Read The API

- Prefer facade names over internal domain types when wiring app features.
- Treat initializer labels as trust-boundary signals: `privateAccount` means the facade can reserve or move wallet-owned value.
- Use descriptor-backed surfaces for public-chain sync whenever mnemonic/private account authority is not required.
- Use [Recipes](recipes.md) for task-shaped examples and [Trust Boundaries](trust-boundaries.md) for security posture.

## Wallet And Account Facades

### `WalletManagementInteractor`

Broad wallet management around an existing `OpalBase.Wallet`. Use it for account creation, account lookup, account count, and wallet snapshot composition when the caller already has wallet authority.

Typical tasks: create the first account, fetch an account by unhardened index, and prepare a wallet for app-owned storage.

### `WalletAccountPublicDescriptor`

Public account handoff for sync and receive lanes. It contains a serialized account extended public key, derivation metadata, and an account snapshot, and can create a read-only `OpalBase.Account`.

Typical tasks: run public-chain sync without mnemonic, Keychain, Secure Enclave, or root private account authority.

### `WalletReceiveAddressInteractor`

Receive-address lane for derivation, reservation, and address cache validity. `reserveNextReceivingDerivedAddress()` is the receive-flow method; `selectNextDerivedAddress(for:)` is inspection-only.

Typical tasks: reserve a CashAddr receive address before showing it to a payer, list derived receiving/change addresses, and persist the resulting account snapshot.

## Public-Chain And Network Facades

### `WalletTransportInteractor`

Public transport lane for chain readers, broadcast clients, and public streams. It can wrap `WalletPublicChainOperations` directly or derive them from `OpalBase.Network.Fulcrum.Client`.

Typical tasks: connect to Fulcrum, subscribe to an address, subscribe to tip updates, and provide readers to sync or broadcast lanes.

### `WalletPublicChainOperations`

Small dependency container for public-chain operations: address reader, transaction client, optional transaction reader, and optional block header reader.

Typical tasks: inject test doubles, custom Fulcrum adapters, or app-specific public-chain clients into sync and broadcast features.

### `WalletBlockchainSyncInteractor`

Descriptor-backed public-chain sync lane for balances, transaction history, UTXOs, and confirmation freshness.

Typical tasks: refresh BCH balances, include or exclude unconfirmed history, refresh UTXOs, update named transaction hashes, refresh all cached confirmations, and emit a new account snapshot.

### `WalletBroadcastInteractor`

Broadcast lane for transaction relay and targeted post-broadcast confirmation reconciliation. It owns a transaction client and does not need mnemonic authority.

Typical tasks: broadcast a prepared transaction, fetch confirmation status for a transaction hash, and reconcile confirmations for transaction hashes named by the caller.

## Secret, Snapshot, And Security Facades

### `WalletSecretAccessInteractor`

Secret-loading and wipe lane for mnemonic, Keychain, Secure Enclave, migration, and recovery flows.

Typical tasks: save wallet secrets and snapshot, restore wallet secrets and snapshot, wipe wallet secrets and snapshots, and apply a `WalletSecurityProfile` secret persistence policy.

### `WalletSnapshotInteractor`

Snapshot-only storage/import-export lane. This surface moves `OpalBase.Wallet.Snapshot` values and must not retain transport clients, raw transactions, or secrets.

Typical tasks: save/load/delete wallet snapshots by generation and save/load/delete the committed generation marker.

### `WalletSecurityProfile`

Security posture contract for secret persistence, network posture, and signing review boundaries. `offlineSavingsSigner` requires Secure Enclave-backed secret persistence, `networkAccess: .offline` with no public-chain sync or relay, and external signing review.

Typical tasks: make offline signer posture explicit, fail closed on weaker secret persistence, and prevent broadcast from profiles that do not allow network relay.

## Money Movement Facades

### `WalletTransactionAuthoringInteractor`

User-triggered money-movement lane. Its initializer label is `privateAccount` because the facade can reserve wallet-owned inputs, reserve change addresses, prepare signing-capable plans, and build funding plans.

Typical tasks: prepare BCH spends, prepare external-review unsigned BCH spends, prepare token spends, prepare token genesis, prepare token mint, prepare token commitment mutation, reserve AnyHedge participant material, and prepare AnyHedge funding.

### `WalletUnsignedSpendPlan`

Reserved spend plan for external transaction review and signing without retained private-key material. It carries a `WalletUnsignedTransactionEnvelope`, selected UTXO/change reservation lifecycle, and completion/cancellation methods.

Typical tasks: hand an unsigned Bitcoin Cash transaction to an external signing flow, complete reservation after a structurally matching signed transaction returns, or cancel the reservation when review is abandoned.

### `WalletUnsignedTransactionEnvelope`

External signing boundary scaffold. It carries an unsigned Bitcoin Cash transaction, transaction outputs being spent, and requested signature format.

Typical tasks: pass review material to an app-owned QR, file, hardware-device, or offline UI flow without exposing account internals.

## Token, Fusion, Hedge, Claimable, And Diagnostics Facades

### `WalletAssetInteractor`

Asset lane for token holdings and token metadata. Read-oriented inventory/metadata operations can use `account`; mint authoring remains explicit through the `privateAccount` initializer.

Typical tasks: load token inventory, fetch/upsert token metadata through a metadata wallet, make a token metadata snapshot, and prepare token minting when private account authority is intentionally provided.

### `CashFusionInteractor`

macOS CashFusion lane for session lifecycle and coordinator state using explicit wallet-owned private account authority.

Typical tasks: evaluate CashFusion readiness and prepare a CashFusion session from a caller-provided coordinator configuration and request.

### `ClaimableInteractor`

Claimable contract lane for drafts, funding outputs, envelopes, status resolution, claim/refund transaction building, and recovery material without turning Claimable into a wallet/account backdoor.

Typical tasks: create and decode claimable envelopes, resolve local/network claimability, build claim/refund transactions, and handle share/recovery material.

### `WalletObservabilityInteractor`

Observability lane for redacted `OpalDiagnostics` records only.

Typical tasks: read recent diagnostics records filtered by category, level, trace ID, event, or date range.

## Domain Vocabulary

These primitives are intentionally public because they are part of the Bitcoin Cash domain contract:

- `OpalBase.Address`
- `OpalBase.Satoshi`
- `OpalBase.Transaction`
- `OpalBase.Transaction.Hash`
- `OpalBase.Transaction.Output.Unspent`
- `OpalBase.Block`
- `OpalBase.Network.Configuration`
- `OpalBase.Network.Fulcrum.Client`
- `OpalBase.Key.SigningKey`
- `OpalBase.WalletUnsignedSpendPlan`
- `OpalBase.WalletUnsignedTransactionEnvelope`

## Where To See It Running

- `Tests/OpalBaseLocalTests/PublicAPISmokeValidator.swift` covers public-surface composition across wallet, descriptor, receive, storage, token metadata, CashFusion, AnyHedge, claimable, and diagnostics areas.
- `Tests/OpalBaseLocalTests/WalletTrustDomainInteractorValidator.swift` checks trust-domain interactor separation.
- `Tests/OpalBaseLocalTests/WalletSecurityProfileValidator.swift` checks offline signer posture and secret persistence policy behavior.
- `Tests/OpalBaseNetworkTests/NetworkLiveSmokeValidator.swift` shows opt-in live Fulcrum usage behind `OPAL_RUN_LIVE_NETWORK_TESTS` and `OPAL_FULCRUM_URL`.
