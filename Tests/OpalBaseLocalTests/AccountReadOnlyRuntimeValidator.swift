// AccountReadOnlyRuntimeValidator.swift

import Foundation
import OpalCrypto
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Account read-only account extended public key runtime", .tags(.unit, .wallet))
struct AccountReadOnlyRuntimeValidator {
    enum DescriptorValidationCase: CaseIterable, CustomStringConvertible, Sendable {
        case invalidSerializedAccountExtendedPublicKey
        case rootExtendedPublicKey
        case accountMismatch
        case snapshotMismatch

        var description: String {
            switch self {
            case .invalidSerializedAccountExtendedPublicKey:
                "invalid serialized account extended public key"
            case .rootExtendedPublicKey:
                "root extended public key"
            case .accountMismatch:
                "account mismatch"
            case .snapshotMismatch:
                "snapshot mismatch"
            }
        }
    }

    enum PrivateKeyRequiredOperationCase: CaseIterable, CustomStringConvertible, Sendable {
        case bitcoinCashSpend
        case tokenSpend
        case tokenGenesis
        case tokenMint
        case tokenCommitmentMutation
        case cashFusionReservation
        case hedgeParticipantMaterial
        case hedgeFunding

        var description: String {
            switch self {
            case .bitcoinCashSpend:
                "Bitcoin Cash spend"
            case .tokenSpend:
                "token spend"
            case .tokenGenesis:
                "token genesis"
            case .tokenMint:
                "token mint"
            case .tokenCommitmentMutation:
                "token commitment mutation"
            case .cashFusionReservation:
                "CashFusion reservation"
            case .hedgeParticipantMaterial:
                "hedge participant material"
            case .hedgeFunding:
                "hedge funding"
            }
        }
    }

    static func makeReadOnlyAccount(
        from privateAccount: OpalBase.Account,
        account: UInt32 = 0
    ) async throws -> OpalBase.Account {
        try await makeReadOnlyAccount(
            snapshot: await privateAccount.makeSnapshot(),
            account: account
        )
    }

    static func makeReadOnlyAccount(
        snapshot: OpalBase.Account.Snapshot,
        account: UInt32 = 0
    ) async throws -> OpalBase.Account {
        try await OpalBase.Account(
            serializedAccountExtendedPublicKey: makeSerializedAccountExtendedPublicKey(account: account),
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: account,
            snapshot: snapshot
        )
    }

    static func makeSerializedAccountExtendedPublicKey(account: UInt32 = 0) throws -> String {
        try makeMnemonic().makeSerializedAccountExtendedPublicKey(account: account)
    }

    static func makeMnemonic() throws -> OpalBase.Key.Mnemonic {
        try OpalBase.Key.Mnemonic(
            phrase: AccountTestFixtures.mnemonicWords.joined(separator: " "),
            language: .english
        )
    }

    static func makeRootExtendedPublicKey() throws -> String {
        try OpalCrypto.Key.ExtendedPrivate.root(
            seed: AccountTestFixtures.makeMnemonic().deriveSeed()
        ).publicKey.serialize()
    }

    static func makeUnspentOutput(
        address: OpalBase.Address,
        value: UInt64 = 10_000,
        hashByte: UInt8
    ) -> OpalBase.Transaction.Output.Unspent {
        OpalBase.Transaction.Output.Unspent(
            value: value,
            lockingScript: address.lockingScript.data,
            previousTransactionHash: AccountTestFixtures.makeHash(byte: hashByte),
            previousTransactionOutputIndex: 0
        )
    }

    static func makeHedgeParticipantMaterial(
        from participant: OpalBase.Hedge.ParticipantMaterial,
        lockingScriptHex: String
    ) -> OpalBase.Hedge.ParticipantMaterial {
        OpalBase.Hedge.ParticipantMaterial(
            side: participant.side,
            payoutAddress: participant.payoutAddress,
            lockingScriptHex: lockingScriptHex,
            mutualRedeemPublicKeyHex: participant.mutualRedeemPublicKeyHex,
            derivedAddress: participant.derivedAddress
        )
    }

    static func listUsedEntryIndexes(
        in entries: [OpalBase.Account.Snapshot.AddressBook.Entry]
    ) -> [UInt32] {
        entries.filter(\.isUsed).map(\.index).sorted()
    }
}
