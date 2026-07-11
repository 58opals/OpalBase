# BCH Builder Starter Guide

This guide is the fastest path from an empty Apple-platform Swift target to the public Opal Base surfaces most Bitcoin Cash apps need first: wallet creation or restore, CashAddr receive-address reservation, Fulcrum-backed public-chain refresh, and BCH spend preparation for external review.

## What Opal Base Is

Opal Base is the Bitcoin Cash application layer in the Opal package stack. It owns wallet/account orchestration, deterministic CashAddr derivation and reservation, BCH balance/history/UTXO refresh, spend planning, transaction construction, wallet snapshots, storage helpers, CashTokens metadata, CashFusion wallet preparation, AnyHedge wallet funding preparation, and redacted diagnostics integration.

Use it when you want app-facing Bitcoin Cash wallet behavior on Apple platforms without directly composing raw cryptography, raw Fulcrum transport, CashFusion coordinator protocol logic, AnyHedge contract primitives, or diagnostics infrastructure.

## What Opal Base Is Not

- It is not a UI framework or app shell.
- It is not a hardware-wallet firmware layer, QR transport, or offline-signing ceremony.
- It is not the raw cryptography package; `OpalCrypto` owns key and signing primitives.
- It is not the raw Fulcrum protocol package; `SwiftFulcrum` owns low-level transport.
- It is not the CashFusion protocol runtime; `OpalFusion` owns coordinator/session protocol behavior.
- It is not the AnyHedge primitive package; `OpalHedge` owns contract-level primitives.
- It is not a place to store mnemonics, passphrases, private keys, transaction review payloads, or recovery material in logs.

## 1. Install The Package

For released-package consumers, depend on the latest tag:

```swift
dependencies: [
    .package(url: "https://github.com/58opals/OpalBase.git", from: "0.4.1")
]
```

For public builder review of unreleased APIs, depend on the public `develop` branch or a specific public revision:

```swift
dependencies: [
    .package(url: "https://github.com/58opals/OpalBase.git", branch: "develop")
]
```

What you have now: your app target can import `OpalBase`. Branch-based dependency use is for review and integration testing; do not present `develop` as a SemVer release.

## 2. Create A Wallet And First Account

Create mnemonic-backed wallet authority only inside the app component that is allowed to handle secrets:

```swift
import Foundation
import OpalBase

let mnemonic = try OpalBase.Key.Mnemonic.generate(
    length: .words12,
    language: .english
)
let wallet = try OpalBase.Wallet(mnemonic: mnemonic)
let management = OpalBase.WalletManagementInteractor(wallet: wallet)

try await management.addAccount(unhardenedIndex: 0)
let account = try await management.fetchAccount(at: 0)
```

What you have now: `wallet` carries mnemonic-backed authority, `account` carries private account authority, and both are actor-isolated. Keep them in a secret-bearing lane and expose narrower interactors to UI, sync, receive, and broadcast components.

## 3. Restore A Wallet Or Build A Public Descriptor

For mnemonic-bearing restore flows, use `WalletSecretAccessInteractor` with `OpalBase.Storage.PersistenceSession`:

```swift
let session = await OpalBase.Storage.PersistenceSession(storage: storage)
let secrets = OpalBase.WalletSecretAccessInteractor(persistenceSession: session)
let restored = try await secrets.restoreWalletSecretsAndSnapshot()

if let storedMnemonic = restored.mnemonic,
   let snapshot = restored.walletSnapshot {
    let mnemonic = try OpalBase.Key.Mnemonic(
        phrase: storedMnemonic.words.joined(separator: " ")
    )
    let restoredWallet = try await OpalBase.Wallet(
        mnemonic: mnemonic,
        passphrase: storedMnemonic.passphrase,
        from: snapshot
    )
}
```

What you have now: a restored wallet can include mnemonic words, passphrase, wallet snapshot, and the protection mode that was used for secret persistence. Apps decide whether missing snapshot or mnemonic material is recoverable for their flow.

For public-chain sync without mnemonic authority, persist and pass a `WalletAccountPublicDescriptor`:

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

What you have now: descriptor-backed components can refresh public-chain state without mnemonic, Keychain, Secure Enclave, or root private account authority.

## 4. Reserve A CashAddr Receive Address

Use the receive-address interactor when an address is being handed out to a payer:

```swift
let receiveAddresses = OpalBase.WalletReceiveAddressInteractor(account: account)
let receiving = try await receiveAddresses.reserveNextReceivingDerivedAddress()

print(receiving.address.string)
```

What you have now: a reserved CashAddr receive address and updated reservation/cache state. Use `reserveNextReceivingDerivedAddress()` for receive flows because it avoids concurrent reuse; use `selectNextDerivedAddress(for:)` only when inspecting the next derived address without handing it out.

## 5. Connect To Fulcrum

Create public-chain transport from a Fulcrum client, then pass only public-chain operations into sync components:

```swift
let configuration = OpalBase.Network.Configuration(
    serverURLs: [URL(string: "wss://your.fulcrum.example:50004")!],
    network: .mainnet
)
let client = try await OpalBase.Network.Fulcrum.Client(configuration: configuration)
let transport = OpalBase.WalletTransportInteractor(fulcrumClient: client)
```

What you have now: `transport.publicChain` wraps address, transaction, and header readers for public Bitcoin Cash chain data. It must not own mnemonics, private keys, passphrases, Secure Enclave state, or wallet snapshots.

## 6. Refresh BCH Balances, History, UTXOs, And Confirmations

Use `WalletBlockchainSyncInteractor` for descriptor-backed public-chain refresh:

```swift
let sync = try await OpalBase.WalletBlockchainSyncInteractor(
    accountDescriptor: descriptor,
    publicChain: transport.publicChain
)

let balanceRefresh = try await sync.refreshBalances(includeUnconfirmedHistory: true)
let historyChanges = try await sync.refreshTransactionHistory(includeUnconfirmed: true)
let utxoRefresh = try await sync.refreshUTXOSet()
let confirmationChanges = try await sync.refreshTransactionConfirmations()
let refreshedSnapshot = await sync.makeSnapshot()
```

What you have now: refreshed BCH balances, transaction history, UTXOs, confirmations, and a snapshot that can be persisted by your app. Confirmed and unconfirmed values are distinct; unconfirmed balances and transactions can change at the mempool level. A transaction output is any output in a transaction; a UTXO is an unspent transaction output available for selection.

## 7. Prepare A BCH Spend For External Review

Build a BCH payment in satoshis, then prepare an external-review unsigned spend plan:

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

What you have now: a `WalletUnsignedSpendPlan` that reserves selected UTXOs and the change address, carries the unsigned Bitcoin Cash transaction plus the transaction outputs being spent, and does not retain private-key material. After an app-owned external signing flow returns a structurally matching signed transaction, complete the reservation with `completeExternalSigning(with:)`. This completion is structural validation only; it does not execute Bitcoin Cash script, cryptographically verify signatures, or broadcast.

## 8. Keep Secret-Handling And Signing Boundaries Explicit

- Use `WalletSecretAccessInteractor` for mnemonic-bearing save, restore, and wipe flows.
- Use `OpalBase.Storage.makeSecureEnclaveBacked` plus `.requireSecureEnclave` or `WalletSecurityProfile.offlineSavingsSigner` when the app must fail closed on weaker secret persistence.
- Secure Enclave storage protects persisted mnemonic material at rest; it does not move BCH secp256k1 transaction signing into the Secure Enclave.
- Use `OpalBase.Key.SigningKey` for scoped in-process secp256k1 signing when raw private-key import is intentional.
- Keep QR exchange, file exchange, hardware-device policy, offline review UI, signature verification policy, and final relay boundaries in the application layer.

## 9. Place Advanced BCH Features Deliberately

- CashTokens: use `OpalBase.CashTokens.*` for token vocabulary and BCMR metadata, `WalletAssetInteractor` for token holdings/metadata, and `WalletTransactionAuthoringInteractor` for token spend, genesis, mint, and commitment-mutation plans.
- CashFusion: use `CashFusionInteractor(privateAccount:)` on macOS for wallet-backed session lifecycle. CashFusion requires private account authority because it reserves wallet-owned inputs and signs host-owned fusion transactions.
- AnyHedge: use `OpalBase.Hedge` through `WalletTransactionAuthoringInteractor` for wallet-facing participant reservation and BCH funding preparation without importing `OpalHedge` directly.
- Diagnostics: use `WalletObservabilityInteractor` and `OpalDiagnostics` records for redacted diagnostics. Do not pass secret material into generic logging paths.

## Tests That Demonstrate Public API Usage

- `Tests/OpalBaseLocalTests/PublicAPISmokeValidator.swift` shows wallet, descriptor, receive, storage, CashFusion, CashTokens, claimable, hedge, and diagnostics-facing public API composition.
- `Tests/OpalBaseLocalTests/WalletTrustDomainInteractorValidator.swift` checks trust-domain interactor boundaries.
- `Tests/OpalBaseLocalTests/WalletSecurityProfileValidator.swift` checks offline signer and secret persistence policy behavior.
- `Tests/OpalBaseNetworkTests/NetworkLiveSmokeValidator.swift` is the opt-in live Fulcrum smoke test using `OPAL_FULCRUM_URL` and `OPAL_RUN_LIVE_NETWORK_TESTS`.

Run local validation with:

```bash
swift build
swift test
```

Run live Fulcrum validation only when you intentionally want network access:

```bash
OPAL_RUN_LIVE_NETWORK_TESTS=1 OPAL_FULCRUM_URL=wss://your.fulcrum.example:50004 swift test --filter NetworkLiveSmokeValidator
```
