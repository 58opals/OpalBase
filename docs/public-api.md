# Public API Guide

Opal Base exposes a workflow-shaped API under the `OpalBase.*` namespace. Normal wallet integrations should start from lane-explicit facade types and only drop to lower-level primitives when they need custom storage, networking, or Bitcoin Cash transaction handling.

## Main Entry Points

- `OpalBase.WalletManagementInteractor`: account creation, account lookup, and broad wallet management around an existing `OpalBase.Wallet`.
- `OpalBase.WalletSnapshotInteractor`: snapshot-only storage/import-export through `OpalBase.Storage.SnapshotPersistence`.
- `OpalBase.WalletBlockchainSyncInteractor`: descriptor-backed balance/history/UTXO/confirmation refresh using `OpalBase.WalletAccountPublicDescriptor` plus `OpalBase.WalletPublicChainOperations`.
- `OpalBase.WalletTransportInteractor`: public-chain transport clients and address/header streams through `OpalBase.Network.*` or `OpalBase.Network.Fulcrum.Client`.
- `OpalBase.WalletReceiveAddressInteractor`: receive/change derivation and receive-address reservation.
- `OpalBase.WalletSecretAccessInteractor`: mnemonic, Keychain, Secure Enclave-backed persistence, restore, and wipe through `OpalBase.Storage.PersistenceSession`.
- `OpalBase.WalletTransactionAuthoringInteractor`: user-triggered BCH spend, token spend, token genesis, token mint, token commitment mutation, hedge funding, and signing-capable plans; its constructor label is `privateAccount`.
- `OpalBase.WalletBroadcastInteractor`: transaction relay and targeted confirmation reconciliation through `OpalBase.Network.TransactionClient`.
- `OpalBase.WalletAssetInteractor`: token holdings and wallet token metadata; mint authoring is available only through its `privateAccount` initializer.
- `OpalBase.CashFusionInteractor`: macOS CashFusion session lifecycle over explicit private account authority.
- `OpalBase.ClaimableInteractor`: claimable drafts, funding outputs, envelopes, share/recovery material, status, claim, and refund transaction building.
- `OpalBase.WalletObservabilityInteractor`: redacted diagnostics record reading only.

## Wallet Creation And Restoration

Create a wallet from a mnemonic, add an account, then fetch the account by its unhardened index:

```swift
let mnemonic = try OpalBase.Key.Mnemonic.generate(
    length: .words12,
    language: .english
)
let wallet = try OpalBase.Wallet(mnemonic: mnemonic)
let management = OpalBase.WalletManagementInteractor(wallet: wallet)

try await management.addAccount(unhardenedIndex: 0)
let account = try await management.fetchAccount(at: 0)
```

For descriptor persistence, callers can derive the account-level read-only extended public key from mnemonic material without importing lower-level cryptography packages:

```swift
let accountXpub = try mnemonic.makeSerializedAccountExtendedPublicKey(
    passphrase: passphrase,
    purpose: .bip44,
    coinType: .bitcoinCash,
    account: 0
)
```

To restore from persisted state, use `OpalBase.WalletSecretAccessInteractor` for mnemonic-bearing restore/wipe flows and `OpalBase.WalletSnapshotInteractor` for snapshot-only import/export. Custom import/export layers can use `OpalBase.Wallet.Snapshot`, `OpalBase.Account.Snapshot`, and `OpalBase.Storage.SnapshotStore`.

For descriptor-only public-chain sync, keep the mnemonic in the secret lane and pass only public account data to sync:

```swift
let descriptor = OpalBase.WalletAccountPublicDescriptor(
    serializedAccountExtendedPublicKey: accountXpub,
    purpose: .bip44,
    coinType: .bitcoinCash,
    accountUnhardenedIndex: 0,
    snapshot: accountSnapshot
)
let publicChain = OpalBase.WalletPublicChainOperations(
    addressReader: addressReader,
    transactionClient: transactionClient,
    transactionReader: transactionReader
)
let sync = try await OpalBase.WalletBlockchainSyncInteractor(
    accountDescriptor: descriptor,
    publicChain: publicChain
)
```

## Receiving Addresses

Use receive-address lane APIs instead of address-book internals:

```swift
let receiveAddresses = OpalBase.WalletReceiveAddressInteractor(account: account)
let receiving = try await receiveAddresses.reserveNextReceivingDerivedAddress()
print(receiving.address.string)
```

Use `selectNextDerivedAddress(for:)` when the caller only needs to inspect the next address for a derivation usage. Use `reserveNextReceivingDerivedAddress()` when the address is being handed out and should not be reused by another concurrent receive flow. This is intentionally not a generic sync API because reservation crosses into derivation/reservation authority.

## Spend Planning

Build a `Payment`, then ask the account to prepare the spend:

```swift
let payment = OpalBase.Account.Payment(
    recipients: [
        .init(address: destination, amount: try OpalBase.Satoshi(10_000))
    ],
    coinSelection: .branchAndBound,
    tokenInputPolicy: .excludeTokenUTXOs
)

let feePolicy = OpalBase.Wallet.FeePolicy(defaultFeeRate: 1)
let authoring = OpalBase.WalletTransactionAuthoringInteractor(
    privateAccount: account,
    feePolicy: feePolicy
)
let plan = try await authoring.prepareSpend(payment)
let result = try plan.buildTransaction()
```

Spend plans expose wallet-facing results such as `OpalBase.Account.DerivedAddress` for change. Reservation and address-book machinery remains behind the account facade.

## Fulcrum Sync

Use `OpalBase.WalletTransportInteractor` to make public-chain transport clients, then choose descriptor sync or legacy wallet Fulcrum composition:

```swift
let client = try await OpalBase.Network.Fulcrum.Client(configuration: configuration)
let transport = OpalBase.WalletTransportInteractor(fulcrumClient: client)
let publicChain = transport.publicChain
let sync = try await OpalBase.WalletBlockchainSyncInteractor(
    accountDescriptor: descriptor,
    publicChain: publicChain
)

_ = try await sync.refreshBalances()
_ = try await sync.refreshTransactionHistory()
if let fulcrum = transport.makeWalletFulcrumAdapter() {
    let monitor = fulcrum.makeMonitor(for: account)
}
```

Closure-backed clients stay public for tests and custom adapters:

- `OpalBase.Network.AddressReader`
- `OpalBase.Network.TransactionClient`
- `OpalBase.Network.TransactionReader`
- `OpalBase.Network.BlockHeaderReader`

Advanced Fulcrum readers are public under `OpalBase.Network.Fulcrum.*`:

- `OpalBase.Network.Fulcrum.TransactionReader`
- `OpalBase.Network.Fulcrum.TransactionProofReader`
- `OpalBase.Network.Fulcrum.ScriptHashReader`

Prefer `WalletBlockchainSyncInteractor` when the Wallet lane has only descriptor/public account state. Prefer `Wallet.Fulcrum` only when composing the older wallet/account actor orchestration directly.

## Broadcast And Aftermath

Broadcast does not imply a whole-wallet rebuild. Use `WalletBroadcastInteractor` to relay a prepared transaction and reconcile only the transaction hashes the caller names:

```swift
let broadcast = OpalBase.WalletBroadcastInteractor(transactionClient: transactionClient)
let hash = try await broadcast.broadcast(result.transaction)
_ = try await broadcast.reconcileConfirmations(for: [hash], in: account)
```

## Persistence

For mnemonic-bearing app persistence, prefer the secret lane:

```swift
let session = await OpalBase.Storage.PersistenceSession(storage: storage)
let secrets = OpalBase.WalletSecretAccessInteractor(persistenceSession: session)
let protectionMode = try await secrets.saveWalletSecretsAndSnapshot(
    from: wallet,
    policy: .legacyFallbackToPlaintext
)
let restored = try await secrets.restoreWalletSecretsAndSnapshot()
```

For SwiftData-backed UI snapshots or import/export without secrets, use `WalletSnapshotInteractor` with `Storage.SnapshotPersistence` and pass `Wallet.Snapshot` values only.

The public storage contract is:

- `OpalBase.Storage.PersistenceSession`
- `OpalBase.Storage.SnapshotStore`
- `OpalBase.Storage.StoredMnemonicStore`
- `OpalBase.Wallet.Snapshot`
- `OpalBase.Account.Snapshot`

Direct account/address-book snapshot operations are implementation details. Snapshot data is still public for storage adapters and import/export, but it no longer exposes `Address.Book` names.

## CashTokens And BCMR

CashTokens domain types remain public vocabulary:

- `OpalBase.CashTokens.TokenData`
- `OpalBase.CashTokens.CategoryID`
- `OpalBase.CashTokens.Metadata`
- `OpalBase.CashTokens.MetadataRepository`
- `OpalBase.CashTokens.BCMR.Client`

Use `WalletAssetInteractor` for token holdings and metadata. Use `WalletTransactionAuthoringInteractor` for token spend, token genesis, token mint planning, and token commitment mutation planning because those are user-triggered money-movement APIs.

## Hedge Funding

Use `OpalBase.Hedge` for the wallet-facing AnyHedge beta flow. Wallets can reserve participant material from an account, pass counterparty material and a verified oracle proof into a USD thirty-day simple hedge request, and prepare the wallet-owned BCH funding spend without importing `OpalHedge`:

```swift
let authoring = OpalBase.WalletTransactionAuthoringInteractor(privateAccount: account)
let walletMaterial = try await authoring.reserveHedgeParticipantMaterial()
let request = OpalBase.Hedge.USDThirtyDaySimpleHedgeRequest(
    walletParticipant: walletMaterial,
    counterpartyParticipant: counterpartyMaterial,
    startingOracleProof: startingOracleProof,
    nominalUnits: 1_000
)

let plan = try await authoring.prepareHedgeFunding(request)
let review = try plan.buildReview()
```

`FundingPlan` keeps the account spend reservation active until the caller builds and broadcasts, completes, or cancels it. A successful `buildAndBroadcast` returns an `OpalBase.Hedge.FundingRecord` with OpalBase-native transaction hash, funding output index, funding amount, and persisted data-document JSON. Settlement summaries can be reconstructed later with `OpalBase.Hedge.makeSettlementSummary(...)` using persisted funding JSON plus verified oracle proofs.

## Claimable

Use `OpalBase.ClaimableInteractor` for claimable contract drafts, funding outputs, envelopes, share codes, local/network status checks, recovery material, and claim/refund transaction building. These APIs are separate from wallet account state so apps can create, decode, inspect, and claim funding envelopes without exposing account internals.

## CashFusion

On macOS, use `OpalBase.CashFusionInteractor(privateAccount:)` for session lifecycle and coordinator state. CashFusion preparation requires private account authority because it reserves wallet-owned inputs and signs host-owned fusion transactions; public-chain transport, broadcast, and snapshots remain outside the CashFusion interactor.

## Domain Vocabulary

These primitives are intentionally public because they are part of the Bitcoin Cash domain contract:

- `OpalBase.Address`
- `OpalBase.Satoshi`
- `OpalBase.Transaction`
- `OpalBase.Transaction.Hash`
- `OpalBase.Block`
- `OpalBase.Network.Configuration`
- `OpalBase.Network.Fulcrum.Client`

Implementation-only reservation state, address-book internals, bridge types, raw lower-level package collaborators, and adapter protocols are not part of the curated public contract. From constructor labels alone, prefer descriptor/public-chain surfaces for sync, `privateAccount` surfaces for signing and money movement, storage/session surfaces for secrets, and snapshot persistence surfaces for import/export DTOs.
