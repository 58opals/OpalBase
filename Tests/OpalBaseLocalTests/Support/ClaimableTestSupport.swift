// ClaimableTestSupport.swift

import Foundation
@testable import OpalBase

enum ClaimableTestSupport {
    static func makeClaimablePrivateKey(lastByte: UInt8) -> Data {
        Data(repeating: 0, count: 31) + Data([lastByte])
    }

    static func makeClaimableDestinationLockingScript(fillByte: UInt8 = 0x33) -> Data {
        var lockingScript = Data()
        lockingScript.append(ScriptOperationCode._DUP.data)
        lockingScript.append(ScriptOperationCode._HASH160.data)
        lockingScript.append(ScriptOperationCode._PUSHBYTES_20.data)
        lockingScript.append(Data(repeating: fillByte, count: 20))
        lockingScript.append(ScriptOperationCode._EQUALVERIFY.data)
        lockingScript.append(ScriptOperationCode._CHECKSIG.data)
        return lockingScript
    }

    static func makeClaimableTransactionHash(
        from rawTransactionData: Data
    ) -> OpalBase.Transaction.Hash {
        OpalBase.Transaction.Hash(naturalOrder: OpalCryptoAdapter.hash256(rawTransactionData))
    }

    static func makeClaimableDraft(
        network: OpalBase.Network.Environment = .chipnet,
        expiryBlockHeight: UInt32 = 500
    ) throws -> (draft: OpalBase.Claimable.Draft, refundPrivateKey: Data) {
        let refundPrivateKey = makeClaimablePrivateKey(lastByte: 0x02)
        let draft = try OpalBase.Claimable.Draft(
            network: network,
            refundPrivateKey: refundPrivateKey,
            expiryBlockHeight: expiryBlockHeight
        )
        return (draft, refundPrivateKey)
    }

    static func makeClaimableEnvelope(
        network: OpalBase.Network.Environment = .chipnet,
        expiryBlockHeight: UInt32 = 500,
        fundingValue: UInt64 = 50_000,
        fundingOutputIndex: UInt32 = 1,
        fundingHashByte: UInt8? = nil
    ) throws -> (envelope: OpalBase.Claimable.Envelope, refundPrivateKey: Data) {
        let claimPrivateKey = makeClaimablePrivateKey(lastByte: 0x01)
        let refundPrivateKey = makeClaimablePrivateKey(lastByte: 0x02)
        let contract = try OpalBase.Claimable.Contract(
            network: network,
            claimPublicKeyHash: try ClaimablePrimitiveOperation.makePublicKeyHash(
                from: claimPrivateKey,
                invalidError: .invalidClaimPrivateKey
            ),
            refundPublicKeyHash: try ClaimablePrimitiveOperation.makePublicKeyHash(
                from: refundPrivateKey,
                invalidError: .invalidRefundPrivateKey
            ),
            expiryBlockHeight: expiryBlockHeight
        )
        let placeholderFundingHash = OpalBase.Transaction.Hash(
            naturalOrder: Data(repeating: fundingHashByte ?? 0x44, count: 32)
        )
        var envelope = try OpalBase.Claimable.Envelope(
            contract: contract,
            claimPrivateKey: claimPrivateKey,
            fundingTransactionHash: placeholderFundingHash,
            fundingOutputIndex: fundingOutputIndex,
            fundingValue: fundingValue
        )
        if fundingHashByte == nil {
            let fundingTransactionData = try makeClaimableFundingTransaction(for: envelope).encode()
            envelope = try replacingFundingTransactionHash(
                in: envelope,
                with: makeClaimableTransactionHash(from: fundingTransactionData)
            )
        }
        return (envelope, refundPrivateKey)
    }

    static func replacingFundingTransactionHash(
        in envelope: OpalBase.Claimable.Envelope,
        with fundingTransactionHash: OpalBase.Transaction.Hash
    ) throws -> OpalBase.Claimable.Envelope {
        try OpalBase.Claimable.Envelope(
            contract: envelope.contract,
            claimPrivateKey: envelope.claimPrivateKey,
            fundingTransactionHash: fundingTransactionHash,
            fundingOutputIndex: envelope.fundingOutputIndex,
            fundingValue: envelope.fundingValue
        )
    }

    static func makeClaimableFundingIdentifier(
        for envelope: OpalBase.Claimable.Envelope
    ) -> String {
        envelope.fundingTransactionHash.reverseOrder.hexadecimalString
    }

    static func makeClaimableHistoryEntry(
        transactionHash: OpalBase.Transaction.Hash,
        blockHeight: Int = 500
    ) -> OpalBase.Network.TransactionHistoryEntry {
        OpalBase.Network.TransactionHistoryEntry(
            transactionIdentifier: transactionHash.reverseOrder.hexadecimalString,
            blockHeight: blockHeight,
            fee: nil
        )
    }

    static func makeClaimableScriptHashReader(
        history: [OpalBase.Network.TransactionHistoryEntry],
        unspentOutputs: [OpalBase.Transaction.Output.Unspent]
    ) -> OpalBase.Network.ScriptHashReader {
        OpalBase.Network.ScriptHashReader(
            fetchHistory: { _, _ in history },
            fetchUnspent: { _, _ in unspentOutputs }
        )
    }

    static func makeClaimableTransactionReader(
        rawTransactionsByHash: [OpalBase.Transaction.Hash: Data]
    ) -> OpalBase.Network.TransactionReader {
        OpalBase.Network.TransactionReader { transactionHash in
            guard let rawTransaction = rawTransactionsByHash[transactionHash] else {
                throw OpalBase.Transaction.Error.transactionNotFound
            }
            return rawTransaction
        }
    }

    static func makeClaimableFundingTransaction(
        for envelope: OpalBase.Claimable.Envelope,
        output: OpalBase.Transaction.Output? = nil
    ) -> OpalBase.Transaction {
        let fallbackOutput = OpalBase.Transaction.Output(
            value: 1_000,
            lockingScript: Data([ScriptOperationCode._1.rawValue])
        )
        let outputCount = Int(envelope.fundingOutputIndex) + 1
        var outputs = Array(repeating: fallbackOutput, count: outputCount)
        outputs[Int(envelope.fundingOutputIndex)] = output ?? OpalBase.Transaction.Output(
            value: envelope.fundingValue,
            lockingScript: envelope.contract.fundingLockingScriptData
        )

        return OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: .init(naturalOrder: Data(repeating: 0xaa, count: 32)),
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data()
                )
            ],
            outputs: outputs,
            lockTime: 0
        )
    }

    static func decodeClaimableUnlockingScript(
        _ unlockingScript: Data
    ) throws -> (
        signatureWithHashType: Data,
        publicKey: Data,
        branchOpcode: UInt8,
        redeemScriptData: Data
    ) {
        let bytes = Array(unlockingScript)
        var offset = 0
        let signatureWithHashType = try readClaimableTestPushedElement(
            from: bytes,
            offset: &offset
        )
        let publicKey = try readClaimableTestPushedElement(
            from: bytes,
            offset: &offset
        )

        guard offset < bytes.count else {
            throw Data.Error.indexOutOfRange
        }
        let branchOpcode = bytes[offset]
        offset += 1

        let redeemScriptData = try readClaimableTestPushedElement(
            from: bytes,
            offset: &offset
        )
        guard offset == bytes.count else {
            throw Data.Error.indexOutOfRange
        }

        return (
            signatureWithHashType: signatureWithHashType,
            publicKey: publicKey,
            branchOpcode: branchOpcode,
            redeemScriptData: redeemScriptData
        )
    }

    static func readClaimableTestPushedElement(
        from bytes: [UInt8],
        offset: inout Int
    ) throws -> Data {
        guard offset < bytes.count else {
            throw Data.Error.indexOutOfRange
        }

        let opcode = bytes[offset]
        offset += 1

        let count: Int
        switch opcode {
        case 0 ... 75:
            count = Int(opcode)
        case ScriptOperationCode._PUSHDATA1.rawValue:
            guard offset < bytes.count else {
                throw Data.Error.indexOutOfRange
            }
            count = Int(bytes[offset])
            offset += 1
        case ScriptOperationCode._PUSHDATA2.rawValue:
            guard offset + 1 < bytes.count else {
                throw Data.Error.indexOutOfRange
            }
            count = Int(UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8))
            offset += 2
        case ScriptOperationCode._PUSHDATA4.rawValue:
            guard offset + 3 < bytes.count else {
                throw Data.Error.indexOutOfRange
            }
            count = Int(
                UInt32(bytes[offset])
                    | (UInt32(bytes[offset + 1]) << 8)
                    | (UInt32(bytes[offset + 2]) << 16)
                    | (UInt32(bytes[offset + 3]) << 24)
            )
            offset += 4
        default:
            throw Data.Error.indexOutOfRange
        }

        guard offset + count <= bytes.count else {
            throw Data.Error.indexOutOfRange
        }

        let pushedElement = Data(bytes[offset ..< offset + count])
        offset += count
        return pushedElement
    }
}
