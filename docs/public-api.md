# Public API Guide

Opal Base exposes a workflow-shaped API under the `OpalBase.*` namespace. Normal wallet integrations should start from a small set of facade types and only drop to lower-level primitives when they need custom storage, networking, or Bitcoin Cash transaction handling.

## Main Entry Points

- `OpalBase.Wallet`: creates, restores, snapshots, and owns accounts plus wallet-level CashTokens metadata.
- `OpalBase.Account`: derives receiving addresses, refreshes wallet-owned UTXOs, prepares spends, and builds token operations.
- `OpalBase.Wallet.Fulcrum`: orchestrates live Fulcrum refresh, confirmation, history, and monitor flows for wallets and accounts.
- `OpalBase.Network.Fulcrum.Client`: connects to a Fulcrum server and feeds the wallet/network facade adapters.
- `OpalBase.Storage.PersistenceSession`: persists and restores mnemonic and wallet snapshot state.

## Wallet Creation And Restoration

Create a wallet from a mnemonic, add an account, then fetch the account by its unhardened index:

```swift
let mnemonic = try OpalBase.Key.Mnemonic.generate(
    length: .words12,
    language: .english
)
let wallet = try OpalBase.Wallet(mnemonic: mnemonic)

try await wallet.addAccount(unhardenedIndex: 0)
let account = try await wallet.fetchAccount(at: 0)
```

To restore from persisted state, use `OpalBase.Storage.PersistenceSession` when possible. Custom import/export layers can use `OpalBase.Wallet.Snapshot`, `OpalBase.Account.Snapshot`, and `OpalBase.Storage.SnapshotStore`.

## Receiving Addresses

Use account-facing derived address types instead of address-book internals:

```swift
let receiving = try await account.reserveNextReceivingDerivedAddress()
print(receiving.address.string)
```

Use `selectNextDerivedAddress(for:)` when the caller only needs to inspect the next address for a derivation usage. Use `reserveNextReceivingDerivedAddress()` when the address is being handed out and should not be reused by another concurrent receive flow.

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
let plan = try await account.prepareSpend(payment, feePolicy: feePolicy)
let result = try plan.buildTransaction()
```

Spend plans expose wallet-facing results such as `OpalBase.Account.DerivedAddress` for change. Reservation and address-book machinery remains behind the account facade.

## Fulcrum Sync

Use `OpalBase.Wallet.Fulcrum` for normal live wallet flows:

```swift
let client = try await OpalBase.Network.Fulcrum.Client(configuration: configuration)
let fulcrum = OpalBase.Wallet.Fulcrum(client: client)

_ = try await fulcrum.refreshBalances(for: account)
_ = try await fulcrum.refreshTransactionHistory(for: account)
let monitor = fulcrum.makeMonitor(for: account)
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

Prefer `Wallet.Fulcrum` unless the application is composing its own network orchestration.

## Persistence

For app persistence, prefer a session:

```swift
let session = await OpalBase.Storage.PersistenceSession(storage: storage)
let protectionMode = try await session.save(wallet: wallet)
let restored = try await session.restore()
```

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

Use account token operations such as `prepareTokenSpend`, `prepareTokenGenesis`, token mint planning, and token commitment mutation planning for wallet-owned transaction flows.

## Claimable

Use `OpalBase.Claimable` for claimable contract drafts, envelopes, share codes, local status checks, and recovery material. These APIs are separate from wallet account state so apps can create, decode, inspect, and claim funding envelopes without exposing account internals.

## Domain Vocabulary

These primitives are intentionally public because they are part of the Bitcoin Cash domain contract:

- `OpalBase.Address`
- `OpalBase.Satoshi`
- `OpalBase.Transaction`
- `OpalBase.Transaction.Hash`
- `OpalBase.Block`
- `OpalBase.Network.Configuration`
- `OpalBase.Network.Fulcrum.Client`

Implementation-only reservation state, address-book internals, bridge types, and adapter protocols are not part of the curated public contract.
