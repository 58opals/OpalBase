# Opal Base Architecture

Opal Base is the Bitcoin Cash application-layer package in the Opal stack. It sits above raw cryptography and transport packages, and below app UI, persistence policy, offline signing ceremonies, support tooling, and product-specific workflow decisions.

## Package Boundary

| Package | Responsibility |
| --- | --- |
| `OpalBase` | Wallet/account orchestration, CashAddr reservation, BCH balance/history/UTXO/confirmation refresh, spend planning, transaction construction, snapshots, storage helpers, CashTokens metadata, CashFusion wallet preparation, authenticated private-alpha Mosaic wallet recovery and chain reconciliation, and redacted diagnostics integration |
| `OpalCrypto` | Cryptography, seed/key derivation primitives, public key support, and signing primitives |
| `SwiftFulcrum` | Fulcrum protocol transport and low-level network communication |
| `OpalFusion` | CashFusion protocol runtime and Mosaic conformance contracts |
| `OpalDiagnostics` | Shared diagnostics vocabulary, redacted record model, and presentation helpers |

Opal Base owns the app-facing orchestration above those packages. It should not become a UI toolkit, hardware-wallet firmware layer, raw socket library, cross-chain abstraction, or portfolio operations surface.

## Builder Integration Lanes

- Wallet management lane: `WalletManagementInteractor` works around an existing `OpalBase.Wallet` for account creation, account lookup, and snapshot composition.
- Secret lane: `WalletSecretAccessInteractor` owns mnemonic-bearing save, restore, and wipe flows through `OpalBase.Storage.PersistenceSession`; the storage or custom mnemonic-persistence root owns one immutable write policy.
- Snapshot lane: `WalletSnapshotInteractor` moves `OpalBase.Wallet.Snapshot` values without retaining secrets, transport clients, or raw transactions.
- Public-chain lane: `WalletAccountPublicDescriptor`, `WalletPublicChainOperations`, `WalletTransportInteractor`, and `WalletBlockchainSyncInteractor` refresh BCH balances, transaction history, UTXOs, and confirmations from public account data.
- Receive lane: `WalletReceiveAddressInteractor` reserves CashAddr receive addresses and keeps reservation/cache mutation separate from generic sync.
- Money-movement lane: `WalletTransactionAuthoringInteractor(privateAccount:)` prepares BCH spends, token transactions, and external-review unsigned spend plans.
- Broadcast lane: `WalletBroadcastInteractor` relays prepared transactions and reconciles confirmations for explicitly named transaction hashes.
- Asset lane: `WalletAssetInteractor` reads token inventory/metadata and makes token mint authoring explicit when private account authority is supplied.
- CashFusion lane: `CashFusionInteractor(privateAccount:)` is macOS-only and requires wallet-owned private account authority.
- Mosaic research lane: the legacy internal `MosaicTransactionHostActor` continues to cover only the explicit Opal-v0/chipnet and mainnet-alpha.4/mainnet pairs, while the macOS-only `MosaicPrivateAlphaRuntime` facade accepts only the frozen mainnet-alpha.4/mainnet pair. App-facing creation and recovery take a Base-owned exact binding and opaque Fusion recovery bytes, so the app target needs only its direct OpalBase dependency. Fresh application creation persists and exactly reads back Fusion's mandatory initial recovery snapshot before claiming the wallet journal attempt or writing its binding. One Base-owned `SessionOwner` retains the sole Fusion owner, transaction host, and transaction reader across pre-manifest formation, recovery, and post-manifest execution. It exposes phase-specific Base types, centralizes exact persistence/readback and relay publication, enforces one owner and one signature use across value copies, reconstructs authenticated mailbox distributions from canonical app state, adapts synchronous atomic companion journals, timing, and Tor route capabilities, and routes only package-proven completion or abort into terminal evidence. Runtime failure, wallet recovery, and route loss remain recovery-required. One `MosaicPrivateAlphaRecoveryOwner` remains both replay-only transaction host and wallet-recovery authority. The authenticated journal accepts an opaque exact-length field-derived key and owns versioning, scope binding, records, and envelope limits; OpalCrypto owns its HKDF-SHA-256, AES-256-GCM, and SHA-256 calculations without exposing CryptoKit types. The journal records exact prepared leases, signing and commit continuations, guarded broadcast intent and result, chain observations, reorganization or disappearance, finality, terminal disposition, and linear cleanup authorization; after persisted exact terminal disposition, the owner releases only that reservation owner's quarantine. Replayed reserve, finalize, commit, and release callbacks can reproduce only authenticated journal facts; they cannot reopen signer access or begin an in-place retry. A recovered locally signed or commit-intent prefix requires every journal-selected input to remain exactly present before commit; absence stays quarantined and fails before a new intent or committed record. An authenticated committed record is the package proof that selected-input absence is the required downstream postcondition. Broadcast still requires the concrete Fulcrum-derived network capability, an enabled security profile, explicit app approval, and durable approval and exact-intent records before I/O. Key protection, atomic durable storage, enumeration, cross-process exclusion, rollback and deletion detection, finality policy, combined Fusion/Base terminal storage, and physical deletion remain app-owned. The private SPI builds and tests against the tracked public dependency graph in a clean public-URL lane; no public enablement, live mainnet broadcast, or release-readiness claim exists.
- Mosaic durable-inventory boundary: the integrating application, not OpalBase or OpalFusion, owns any durable missing-input tombstone. Its one atomic authenticated inventory/tombstone snapshot must bind the outer-record revision, wallet reservation UUID and generation, Fusion attempt, generation, and material identifiers, the exact outpoint and selected-input payload digest, and the exact committed transaction hash. The application must compare-and-replace and read back that state with wallet inventory, enumerate it at startup, anchor rollback and deletion detection, exclude concurrent processes, and retain it through composed terminal cleanup. Any future capability that classifies an ambiguous commit-intent absence as durably removed by this exact attempt must validate every binding; missing, unknown, stale, tampered, extra, duplicate, rolled-back, deleted, or outcome-uncertain evidence remains fail-closed.
- Diagnostics lane: `WalletObservabilityInteractor` reads redacted diagnostics records only.

## Data Flow

```text
mnemonic/private wallet lane
    -> wallet/account actor state
    -> public descriptor + snapshots
    -> Fulcrum-backed public-chain sync
    -> refreshed account snapshot
```

```text
private account lane
    -> spend/token authoring
    -> signed transaction or external-review unsigned plan
    -> app-owned signing/review/broadcast policy
    -> targeted confirmation reconciliation
```

The first flow can run without mnemonic authority after descriptor construction. The second flow is user-triggered money movement and stays behind `privateAccount` surfaces.

## State And Persistence

Wallet and account objects are actor-isolated so mutation stays serialized. Snapshot persistence is intentionally separate from secret persistence: `WalletSnapshotInteractor` handles snapshot values, while `WalletSecretAccessInteractor` handles mnemonic-bearing state. `Storage` requires an explicit backend, security provider, and construction-bound secret policy; manually composed mnemonic persistence likewise binds the policy once. Existing plaintext and historical Secure Enclave envelopes remain readable. New plaintext writes remain possible when `.legacyFallbackToPlaintext` is explicitly selected or when an explicitly supplied provider returns `.plaintext` under `.acceptProviderOutput`; only `.requireSecureEnclave` fails closed on weaker output.

Secure Enclave-backed persistence protects stored mnemonic material at rest. It does not move BCH secp256k1 signing into the Secure Enclave; apps that need external signing review should use `WalletUnsignedSpendPlan` and keep review, signature verification policy, and relay outside the signing boundary.

## Public-Chain Sync

Descriptor-backed sync starts from `WalletAccountPublicDescriptor` and `WalletPublicChainOperations`. `WalletBlockchainSyncInteractor` can refresh BCH balances, transaction history, UTXOs, and confirmations without root private account authority. Confirmed and unconfirmed state should remain distinct in app UI and storage because unconfirmed state can change at the mempool level.

## Non-Goals

- UI, app shell, onboarding screens, settings screens, or end-user product UX.
- Raw cryptography or key primitive ownership that belongs in `OpalCrypto`.
- Raw Fulcrum protocol ownership that belongs in `SwiftFulcrum`.
- CashFusion coordinator/session protocol ownership that belongs in `OpalFusion`.
- Mosaic interoperability beyond the frozen Opal-v0 and mainnet-alpha.4 contracts, concrete app-session ownership, or public enablement.
- Diagnostics infrastructure ownership that belongs in `OpalDiagnostics`.
- Multi-chain abstractions. Opal Base is Bitcoin Cash-specific.

## Review Pointers

- Start with [BCH Builder Starter Guide](starter-guide.md) for the first-success path.
- Use [Recipes](recipes.md) for task lookup.
- Use [Trust Boundaries](trust-boundaries.md) before wiring secrets, signing, broadcast, or diagnostics.
- Use [Public API Guide](public-api.md) for facade-level reference.
- Use `Tests/OpalBaseLocalTests/PublicAPISmokeValidator.swift` and `Tests/OpalBaseNetworkTests/NetworkLiveSmokeValidator.swift` as runnable public API examples.
