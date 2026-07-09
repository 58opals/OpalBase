# Recipes

Use these recipes when you already know the task you want to perform. Start with the [BCH Builder Starter Guide](starter-guide.md) if you want a linear first-success path, then come back here for copyable integration shapes.

## Create A Wallet And First Account

Use `WalletManagementInteractor` when a secret-bearing component is allowed to create wallet/account authority:

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

Use this when: a new wallet is being created or a restored wallet is being rehydrated into actor-isolated wallet/account objects.

Review with: `Tests/OpalBaseLocalTests/PublicAPISmokeValidator.swift`.

## Restore Wallet Secrets And Snapshot

Use `WalletSecretAccessInteractor` for mnemonic-bearing save, restore, and wipe flows:

```swift
let session = await OpalBase.Storage.PersistenceSession(storage: storage)
let secrets = OpalBase.WalletSecretAccessInteractor(persistenceSession: session)
let restored = try await secrets.restoreWalletSecretsAndSnapshot()
```

Use this when: the component is allowed to handle mnemonic material and storage protection policy.

Do not use this when: the component only needs public-chain balance, history, UTXOs, or confirmations.

Review with: `Tests/OpalBaseLocalTests/StoragePersistenceValidator.swift` and `Tests/OpalBaseLocalTests/WalletSecurityProfileValidator.swift`.

## Persist Snapshot-Only State

Use `WalletSnapshotInteractor` when the component should move wallet snapshots without owning secrets:

```swift
let snapshots = await OpalBase.WalletSnapshotInteractor(storage: storage)
let snapshot = await snapshots.makeSnapshot(from: wallet)

try await snapshots.saveSnapshot(snapshot, generation: "current")
try await snapshots.saveCommittedGeneration("current")
```

Use this when: UI state, import/export, or background sync needs snapshot values without mnemonic authority.

Review with: `Tests/OpalBaseLocalTests/SnapshotPersistenceValidator.swift`.

## Build A Public Account Descriptor

Use `WalletAccountPublicDescriptor` to hand public account state to sync or receive components:

```swift
let accountSnapshot = await account.makeSnapshot()
let accountXpub = try mnemonic.makeSerializedAccountExtendedPublicKey(
    passphrase: "",
    purpose: .bip44,
    coinType: .bitcoinCash,
    account: 0
)

let descriptor = OpalBase.WalletAccountPublicDescriptor(
    serializedAccountExtendedPublicKey: accountXpub,
    purpose: .bip44,
    coinType: .bitcoinCash,
    accountUnhardenedIndex: 0,
    snapshot: accountSnapshot
)
```

Use this when: a component needs CashAddr derivation, BCH balance refresh, transaction history, UTXOs, or confirmations without mnemonic, Keychain, Secure Enclave, or root private account authority.

Review with: `Tests/OpalBaseLocalTests/PublicAPISmokeValidator.swift`.

## Reserve A CashAddr Receive Address

Use `WalletReceiveAddressInteractor` when an address is being handed out to a payer:

```swift
let receiveAddresses = OpalBase.WalletReceiveAddressInteractor(account: account)
let receiving = try await receiveAddresses.reserveNextReceivingDerivedAddress()

print(receiving.address.string)
```

Use this when: a receive flow needs to avoid concurrent address reuse.

Do not substitute: `selectNextDerivedAddress(for:)` when the address is being handed out. Selection inspects; reservation mutates reservation/cache state.

Review with: `Tests/OpalBaseLocalTests/PublicAPISmokeValidator.swift` and `Tests/OpalBaseLocalTests/WalletTrustDomainInteractorValidator.swift`.

## Connect To Fulcrum

Use `WalletTransportInteractor` to convert a Fulcrum client into public-chain operations:

```swift
let configuration = OpalBase.Network.Configuration(
    serverURLs: [URL(string: "wss://your.fulcrum.example:50004")!],
    network: .mainnet
)
let client = try await OpalBase.Network.Fulcrum.Client(configuration: configuration)
let transport = OpalBase.WalletTransportInteractor(fulcrumClient: client)
let publicChain = transport.publicChain
```

Use this when: the component needs public Bitcoin Cash chain data or transaction broadcast clients.

Review with: `Tests/OpalBaseNetworkTests/NetworkLiveSmokeValidator.swift` for opt-in live-network shape.

## Refresh BCH Balance, History, UTXOs, And Confirmations

Use `WalletBlockchainSyncInteractor` for descriptor-backed refresh:

```swift
let sync = try await OpalBase.WalletBlockchainSyncInteractor(
    accountDescriptor: descriptor,
    publicChain: publicChain
)

let balanceRefresh = try await sync.refreshBalances(includeUnconfirmedHistory: true)
let historyChanges = try await sync.refreshTransactionHistory(includeUnconfirmed: true)
let utxoRefresh = try await sync.refreshUTXOSet()
let confirmationChanges = try await sync.refreshTransactionConfirmations()
let snapshot = await sync.makeSnapshot()
```

Use this when: sync should run from public account data. Confirmed and unconfirmed values are distinct; unconfirmed state can change at the mempool level.

Review with: `Tests/OpalBaseLocalTests/AccountReadOnlyRuntimeValidator+Refresh.swift` and `Tests/OpalBaseNetworkTests/AddressBookUnspentTransactionOutputRefreshNetworkValidator.swift`.

## Prepare A BCH Spend For External Review

Use `WalletTransactionAuthoringInteractor(privateAccount:)` when a user-triggered money movement needs private account authority:

```swift
let payment = OpalBase.Account.Payment(
    recipients: [
        .init(address: destination, amount: try OpalBase.Satoshi(10_000))
    ],
    coinSelection: .branchAndBound,
    tokenInputPolicy: .excludeTokenUTXOs
)

let authoring = OpalBase.WalletTransactionAuthoringInteractor(
    privateAccount: account,
    feePolicy: .init(defaultFeeRate: 1)
)

let unsignedPlan = try await authoring.prepareSpendForExternalReview(
    payment,
    profile: .offlineSavingsSigner
)
let envelope = unsignedPlan.envelope
```

Use this when: the app needs an unsigned Bitcoin Cash transaction plus spent transaction outputs for an external signing/review ceremony.

Remember: completing external signing performs structural validation and reservation completion; it does not execute Bitcoin Cash script, cryptographically verify signatures, or broadcast.

Review with: `Tests/OpalBaseLocalTests/StoragePersistenceValidator~SpendValidation.swift` and `Tests/OpalBaseLocalTests/WalletSecurityProfileValidator.swift`.

## Prepare And Broadcast An In-Process BCH Spend

Use `prepareSpend(_:)` when the app intentionally signs in process, then use `WalletBroadcastInteractor` to relay and reconcile targeted confirmations:

```swift
let plan = try await authoring.prepareSpend(payment)
let result = try plan.buildTransaction()

let broadcast = OpalBase.WalletBroadcastInteractor(transactionClient: publicChain.transactionClient)
let hash = try await broadcast.broadcast(result.transaction)
_ = try await broadcast.reconcileConfirmations(for: [hash], in: account)
```

Use this when: the app policy allows in-process signing and online relay.

Review with: `Tests/OpalBaseLocalTests/SpendPlanBroadcastValidator.swift`.

## Read CashTokens Metadata And Holdings

Use `OpalBase.CashTokens.*` for token vocabulary and `WalletAssetInteractor` for wallet-facing token holdings/metadata:

```swift
let assets = OpalBase.WalletAssetInteractor(account: account)
let inventory = try await assets.loadTokenInventory()

let repository = OpalBase.CashTokens.MetadataRepository()
let metadata = await repository.fetchMetadata(for: category)
```

Use `WalletTransactionAuthoringInteractor` for token spend, genesis, mint, and commitment-mutation plans because those are money-movement APIs.

Review with: `Tests/OpalBaseLocalTests/BitcoinCashMetadataRegistryValidator.swift`, `Tests/OpalBaseLocalTests/WalletTokenMetadataSyncValidator.swift`, and token transaction validators under `Tests/OpalBaseLocalTests`.

## Prepare CashFusion

On macOS, use `CashFusionInteractor(privateAccount:)` for wallet-backed session lifecycle:

```swift
#if os(macOS)
let fusion = OpalBase.CashFusionInteractor(privateAccount: account)
let readiness = try await fusion.evaluateReadiness()
#endif
```

Use this when: a wallet-backed CashFusion flow needs to reserve wallet-owned inputs and sign host-owned fusion transactions.

Review with: `Tests/OpalBaseLocalTests/AccountCashFusionReadinessValidator.swift` and `Tests/OpalBaseLocalTests/PublicAPISmokeValidator.swift`.

## Prepare AnyHedge Funding

Use the wallet-facing hedge APIs through `WalletTransactionAuthoringInteractor`:

```swift
let authoring = OpalBase.WalletTransactionAuthoringInteractor(privateAccount: account)
let walletMaterial = try await authoring.reserveHedgeParticipantMaterial()
let request = OpalBase.Hedge.USDThirtyDaySimpleHedgeRequest(
    walletParticipant: walletMaterial,
    counterpartyParticipant: counterpartyMaterial,
    startingOracleProof: startingOracleProof,
    nominalUnits: 1_000
)

let fundingPlan = try await authoring.prepareHedgeFunding(request)
let review = try fundingPlan.buildReview()
```

Use this when: an app needs OpalBase-native wallet reservation and BCH funding preparation without importing `OpalHedge` directly.

Review with: `Tests/OpalBaseLocalTests/HedgeFundingFacadeValidator.swift`.

## Read Redacted Diagnostics

Use `WalletObservabilityInteractor` for diagnostics records that are already redacted through `OpalDiagnostics`:

```swift
let observability = OpalBase.WalletObservabilityInteractor()
let records = observability.recentRecords()
```

Use this when: support or developer tools need package diagnostics without receiving mnemonics, private keys, passphrases, raw recovery payloads, or transaction review payloads.

Review with: `Tests/OpalBaseLocalTests/DiagnosticsValidator.swift` and `Tests/OpalBaseLocalTests/DiagnosticsErrorPresentationValidator.swift`.

## Validation Commands

```bash
swift build
swift test
```

Live Fulcrum validation is intentionally opt-in:

```bash
OPAL_RUN_LIVE_NETWORK_TESTS=1 OPAL_FULCRUM_URL=wss://your.fulcrum.example:50004 swift test --filter NetworkLiveSmokeValidator
```
