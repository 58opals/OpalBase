# Opal Base Architecture

Opal Base is the Bitcoin Cash application-layer package in the Opal stack. It sits above raw cryptography and transport packages, and below app UI, persistence policy, offline signing ceremonies, support tooling, and product-specific workflow decisions.

## Package Boundary

| Package | Responsibility |
| --- | --- |
| `OpalBase` | Wallet/account orchestration, CashAddr reservation, BCH balance/history/UTXO/confirmation refresh, spend planning, transaction construction, snapshots, storage helpers, CashTokens metadata, CashFusion wallet preparation, internal Mosaic wallet-host validation, and redacted diagnostics integration |
| `OpalCrypto` | Cryptography, seed/key derivation primitives, public key support, and signing primitives |
| `SwiftFulcrum` | Fulcrum protocol transport and low-level network communication |
| `OpalFusion` | CashFusion protocol runtime and Mosaic conformance contracts |
| `OpalDiagnostics` | Shared diagnostics vocabulary, redacted record model, and presentation helpers |

Opal Base owns the app-facing orchestration above those packages. It should not become a UI toolkit, hardware-wallet firmware layer, raw socket library, cross-chain abstraction, or portfolio operations surface.

## Builder Integration Lanes

- Wallet management lane: `WalletManagementInteractor` works around an existing `OpalBase.Wallet` for account creation, account lookup, and snapshot composition.
- Secret lane: `WalletSecretAccessInteractor` owns mnemonic-bearing save, restore, and wipe flows through `OpalBase.Storage.PersistenceSession`.
- Snapshot lane: `WalletSnapshotInteractor` moves `OpalBase.Wallet.Snapshot` values without retaining secrets, transport clients, or raw transactions.
- Public-chain lane: `WalletAccountPublicDescriptor`, `WalletPublicChainOperations`, `WalletTransportInteractor`, and `WalletBlockchainSyncInteractor` refresh BCH balances, transaction history, UTXOs, and confirmations from public account data.
- Receive lane: `WalletReceiveAddressInteractor` reserves CashAddr receive addresses and keeps reservation/cache mutation separate from generic sync.
- Money-movement lane: `WalletTransactionAuthoringInteractor(privateAccount:)` prepares BCH spends, token transactions, and external-review unsigned spend plans.
- Broadcast lane: `WalletBroadcastInteractor` relays prepared transactions and reconciles confirmations for explicitly named transaction hashes.
- Asset lane: `WalletAssetInteractor` reads token inventory/metadata and makes token mint authoring explicit when private account authority is supplied.
- CashFusion lane: `CashFusionInteractor(privateAccount:)` is macOS-only and requires wallet-owned private account authority.
- Mosaic research lane: the internal `MosaicTransactionHostActor` is macOS-only and accepts exactly the Opal-v0/chipnet and mainnet-alpha.4/mainnet profile pairs. It binds one non-resumable attempt to token-free P2PKH inputs, fresh receiving outputs, transcript-gated local signing, independent verification of every complete P2PKH Schnorr `ALL|FORKID` input, and terminal commit or pre-sign release. For alpha.4, it requires the supplied excess-fee share to be within the frozen 1–2-satoshi range, rejects legacy alpha.3 transaction-profile identifiers, and verifies `sum(inputs) - sum(outputs) == 141 × inputCount + 34 × outputCount + requiredShare` before journaling or wallet mutation; OpalFusion owns the roster-bound share derivation, while Opal-v0 component-fee behavior remains unchanged. It pins each exact reservation, signing request, and complete transaction before suspending, rechecks cancellation and the lease deadline at the final pre-sign boundaries, and quarantines ambiguous post-intent outcomes for recovery. `TransactionReader` implements the OpalFusion previous-output source contract by validating fetched transaction hashes and canonical bytes and returning the exact indexed output facts; the concrete signing policy then independently refetches and verifies every previous output, enforces canonical transaction ordering and an exact one-satoshi-per-estimated-final-byte fee, and fails before signing on any mismatch. The mainnet-alpha.4 lifecycle proof is a synthetic six-contributor transaction using an in-memory reader. From app-loaded integrity-checked records, the recovery planner identifies the exact terminal or reconciliation requirement and a startup gate re-quarantines matching attempt inputs; a missing journaled input produces wallet reconciliation, while a substituted payload fails without granting broadcast authority. Broadcast accepts only a sealed host-committed or gate-recovered transaction candidate, requires a broadcasting-enabled wallet security profile plus explicit app approval, and durably records approval separately from the exact intent before client I/O. Journal serialization, integrity protection, encryption, loading, missing-input tombstones, output cleanup, wallet and chain reconciliation execution, production client-network binding, live transport, actual mainnet broadcast, and a public session facade remain app-owned or unavailable.
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

Wallet and account objects are actor-isolated so mutation stays serialized. Snapshot persistence is intentionally separate from secret persistence: `WalletSnapshotInteractor` handles snapshot values, while `WalletSecretAccessInteractor` handles mnemonic-bearing state and storage protection policy.

Secure Enclave-backed persistence protects stored mnemonic material at rest. It does not move BCH secp256k1 signing into the Secure Enclave; apps that need external signing review should use `WalletUnsignedSpendPlan` and keep review, signature verification policy, and relay outside the signing boundary.

## Public-Chain Sync

Descriptor-backed sync starts from `WalletAccountPublicDescriptor` and `WalletPublicChainOperations`. `WalletBlockchainSyncInteractor` can refresh BCH balances, transaction history, UTXOs, and confirmations without root private account authority. Confirmed and unconfirmed state should remain distinct in app UI and storage because unconfirmed state can change at the mempool level.

## Non-Goals

- UI, app shell, onboarding screens, settings screens, or end-user product UX.
- Raw cryptography or key primitive ownership that belongs in `OpalCrypto`.
- Raw Fulcrum protocol ownership that belongs in `SwiftFulcrum`.
- CashFusion coordinator/session protocol ownership that belongs in `OpalFusion`.
- Mosaic live transport, runtime mailbox integration, and runtime interoperability beyond the frozen Opal-v0 and mainnet-alpha.4 contracts.
- Diagnostics infrastructure ownership that belongs in `OpalDiagnostics`.
- Multi-chain abstractions. Opal Base is Bitcoin Cash-specific.

## Review Pointers

- Start with [BCH Builder Starter Guide](starter-guide.md) for the first-success path.
- Use [Recipes](recipes.md) for task lookup.
- Use [Trust Boundaries](trust-boundaries.md) before wiring secrets, signing, broadcast, or diagnostics.
- Use [Public API Guide](public-api.md) for facade-level reference.
- Use `Tests/OpalBaseLocalTests/PublicAPISmokeValidator.swift` and `Tests/OpalBaseNetworkTests/NetworkLiveSmokeValidator.swift` as runnable public API examples.
