# Trust Boundaries

Opal Base is designed around narrow integration lanes. The important rule for builders is simple: use public descriptors and transport interactors for public-chain work, and keep mnemonic/private account authority only in the components that are allowed to create, persist, sign, or reserve wallet-owned value.

## Boundary Map

| Boundary | Public Facade | Owns Secrets? | Use It For |
| --- | --- | --- | --- |
| Wallet management | `WalletManagementInteractor` | Yes, through `OpalBase.Wallet` and `OpalBase.Account` | Account creation, account lookup, wallet snapshots |
| Secret persistence | `WalletSecretAccessInteractor` | Yes | Mnemonic-bearing save, restore, wipe, Secure Enclave-backed persistence |
| Snapshot-only persistence | `WalletSnapshotInteractor` | No | Import/export or storage of `Wallet.Snapshot` values without mnemonic authority |
| Public account sync | `WalletAccountPublicDescriptor`, `WalletBlockchainSyncInteractor` | No | BCH balance, transaction history, UTXO, and confirmation refresh from public account data |
| Transport | `WalletTransportInteractor` | No | Fulcrum-backed public-chain readers, streams, and transaction clients |
| Receive address | `WalletReceiveAddressInteractor` | No mnemonic authority, but mutates reservation/cache state | Reserving CashAddr receive addresses and listing derived addresses |
| Money movement | `WalletTransactionAuthoringInteractor(privateAccount:)` | Yes, through private account authority | BCH spends, token spends, token genesis, token mint, token commitment mutation, AnyHedge funding |
| External signing review | `WalletUnsignedSpendPlan`, `WalletUnsignedTransactionEnvelope` | No retained private-key material | Unsigned Bitcoin Cash transaction review and reservation completion after external signing |
| Broadcast | `WalletBroadcastInteractor` | No | Transaction relay and targeted confirmation reconciliation |
| Diagnostics | `WalletObservabilityInteractor` | No | Reading redacted diagnostics records |

## Secret-Bearing Authority

`OpalBase.Wallet` and `OpalBase.Account` are actor-isolated domain objects. A wallet created from a mnemonic and an account fetched from that wallet should be treated as secret-bearing authority because they can derive addresses, reserve wallet-owned value, and participate in signing paths.

Use `WalletSecretAccessInteractor` when code is allowed to save, restore, or wipe mnemonic-bearing state. Use `OpalBase.Storage.makeSecureEnclaveBacked` and `.requireSecureEnclave` when a flow must fail closed instead of falling back to weaker secret persistence.

Secure Enclave-backed storage protects persisted mnemonic material at rest. It does not move BCH secp256k1 transaction signing into the Secure Enclave; once wallet authority is restored, signing still happens through Opal Base and OpalCrypto in process memory unless the app chooses an external signing boundary.

## Public-Chain Sync Without Secrets

`WalletAccountPublicDescriptor` is the handoff object for sync lanes. It contains a serialized account extended public key, derivation metadata, and an account snapshot. It should be enough for public-chain refresh without mnemonic, Keychain, Secure Enclave, or root private account authority.

`WalletBlockchainSyncInteractor` takes a descriptor or read-only account plus `WalletPublicChainOperations`. Use it for BCH balances, transaction history, UTXOs, and confirmations. Confirmed and unconfirmed values must stay distinct because unconfirmed state can change at the mempool level.

## Receive-Address Reservation

A CashAddr receive address should be reserved when it is handed out to a payer. `reserveNextReceivingDerivedAddress()` mutates reservation/cache state so concurrent receive flows do not reuse the same address. `selectNextDerivedAddress(for:)` is for inspection only.

This boundary is not secret-bearing in the mnemonic sense, but it is stateful. Treat receive-address reservation as a write operation in your app architecture.

## Money Movement And `privateAccount`

`WalletTransactionAuthoringInteractor` uses the initializer label `privateAccount` deliberately. BCH spends, token spends, token genesis, token mint, token commitment mutation, AnyHedge participant reservation, and AnyHedge funding preparation all reserve or move wallet-owned value.

Use this facade only in user-triggered money-movement flows. Public-chain sync, address monitoring, and read-only UI refresh should not need it.

## External Signing Review

`prepareSpendForExternalReview(_:profile:signatureFormat:unlockers:)` returns `WalletUnsignedSpendPlan`. The plan reserves selected UTXOs and the change address, and its envelope carries the unsigned Bitcoin Cash transaction plus the transaction outputs being spent.

After the app completes its own external signing flow, `completeExternalSigning(with:)` checks that the signed transaction structurally matches the unsigned plan before completing the reservation. This does not execute Bitcoin Cash script, cryptographically verify signatures, or broadcast. Keep QR exchange, file exchange, hardware-device policy, offline review UI, signature verification policy, and relay in app-owned boundaries.

## Broadcast Separation

Broadcast is separate from spend authoring. `WalletBroadcastInteractor` owns a transaction client and can reconcile confirmations for the transaction hashes the caller names. It does not imply a whole-wallet rebuild and it does not need mnemonic authority.

## Diagnostics

Diagnostics records are intended to be redacted before they are read through `WalletObservabilityInteractor`. Do not add mnemonics, private keys, passphrases, raw recovery payloads, unsigned transaction envelopes, signed transaction payloads, or transaction review payloads to generic logging paths.

## Review Checklist

- Can this component run from `WalletAccountPublicDescriptor` instead of `OpalBase.Wallet` or `OpalBase.Account`?
- Is this flow handing out a CashAddr receive address? If yes, reserve it instead of selecting it.
- Is this flow moving BCH, tokens, or hedge funding value? If yes, keep it behind `WalletTransactionAuthoringInteractor(privateAccount:)`.
- Is this flow external-signing oriented? If yes, keep signing ceremony, signature verification policy, and broadcast outside the unsigned plan.
- Does this log path accept arbitrary values? If yes, keep secret and transaction review payloads out of it.
