// ReusablePaymentAddressFixtureData.swift

import Foundation
@testable import OpalBase

enum ReusablePaymentAddressFixtureData {
    static func makePublicKey(byte: UInt8 = 1) throws -> OpalBase.Key.PublicKey {
        try OpalBase.Key.PublicKey(privateKeyData: Data(repeating: byte, count: 32))
    }

    static func makeTransactionHash(byte: UInt8 = 1) -> OpalBase.Transaction.Hash {
        OpalBase.Transaction.Hash(naturalOrder: Data(repeating: byte, count: 32))
    }

    static func makeOutpoint(byte: UInt8 = 1, outputIndex: UInt32 = 0) -> OpalBase.Transaction.Outpoint {
        OpalBase.Transaction.Outpoint(
            transactionHash: makeTransactionHash(byte: byte),
            outputIndex: outputIndex
        )
    }

    static func makePrefix(bitCount: Int = 12, hashByte: UInt8 = 7) throws -> OpalBase.ReusablePaymentAddress.InputHashPrefix {
        try OpalBase.ReusablePaymentAddress.InputHashPrefix(
            hash: Data(repeating: hashByte, count: 32),
            prefixLength: OpalBase.ReusablePaymentAddress.PrefixLength(bitCount: bitCount)
        )
    }

    static func makeAddress() throws -> OpalBase.ReusablePaymentAddress {
        try OpalBase.ReusablePaymentAddress(
            version: .init(rawValue: 0),
            network: .mainnet,
            prefixLength: .init(bitCount: 12),
            expiration: .never,
            scanPublicKey: makePublicKey(byte: 1),
            spendPublicKey: makePublicKey(byte: 2)
        )
    }

    static func makeInputMetadata() throws -> OpalBase.ReusablePaymentAddress.TransactionInputMetadata {
        try OpalBase.ReusablePaymentAddress.TransactionInputMetadata(
            outpoint: makeOutpoint(),
            inputPublicKey: makePublicKey(byte: 3),
            inputHashPrefix: makePrefix()
        )
    }

    static func makeReceiveCandidate() throws -> OpalBase.ReusablePaymentAddress.ReceiveCandidate {
        try OpalBase.ReusablePaymentAddress.ReceiveCandidate(
            transactionHash: makeTransactionHash(byte: 4),
            blockHeight: 100,
            outputIndex: 1,
            value: 5_000,
            lockingScript: Data([0x51]),
            inputMetadata: [makeInputMetadata()]
        )
    }

    static func makeCandidateTransaction() throws -> OpalBase.ReusablePaymentAddress.CandidateTransaction {
        try OpalBase.ReusablePaymentAddress.CandidateTransaction(
            transactionHash: makeTransactionHash(byte: 5),
            blockHeight: 100,
            rawTransactionData: Data([0x01, 0x02]),
            inputMetadata: [makeInputMetadata()]
        )
    }
}
