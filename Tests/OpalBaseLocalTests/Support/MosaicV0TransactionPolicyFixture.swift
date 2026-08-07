// MosaicV0TransactionPolicyFixture.swift

#if os(macOS)
import Foundation
import OpalCrypto
import OpalFusion
@testable import OpalBase

enum MosaicV0TransactionPolicyFixture {
    struct InputMaterial {
        let rawPreviousTransaction: Data
        let transactionHash: OpalBase.Transaction.Hash
        let transactionInput: OpalBase.Transaction.Input
        let participantInput: OpalFusion.Host.ParticipantInput
    }

    struct Scenario {
        let policy: OpalBase.Account.MosaicV0TransactionPolicy
        let transaction: OpalBase.Transaction
        let request: OpalFusion.Host.MosaicTransactionSigningRequest
        let feeSatoshis: UInt64
    }

    static func makeInputMaterial(
        seed: UInt8 = 1,
        amountSatoshis: UInt64 = 100_000,
        outputIndex: UInt32 = 0,
        previousOutputTokenData: OpalBase.CashTokens.TokenData? = nil,
        previousOutputLockingScript: Data? = nil,
        participantAmountSatoshis: UInt64? = nil,
        participantLockingScript: Data? = nil,
        rawPreviousTransactionOverride: Data? = nil
    ) throws -> InputMaterial {
        let signingKey = try OpalBase.Key.SigningKey(
            rawRepresentation: Data(repeating: seed, count: 32)
        )
        let lockingScript = OpalBase.Script.p2pkh_OPCHECKSIG(
            hash: .init(publicKey: signingKey.publicKey)
        ).data
        let previousTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: .init(
                        naturalOrder: Data(repeating: seed &+ 0x40, count: 32)
                    ),
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data([0x51])
                )
            ],
            outputs: [
                .init(
                    value: amountSatoshis,
                    lockingScript: previousOutputLockingScript ?? lockingScript,
                    tokenData: previousOutputTokenData
                )
            ],
            lockTime: 0
        )
        let rawPreviousTransaction = try rawPreviousTransactionOverride
            ?? previousTransaction.encode()
        let transactionHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCrypto.Hashing.hash256(rawPreviousTransaction)
        )
        return .init(
            rawPreviousTransaction: rawPreviousTransaction,
            transactionHash: transactionHash,
            transactionInput: .init(
                previousTransactionHash: transactionHash,
                previousTransactionOutputIndex: outputIndex,
                unlockingScript: Data()
            ),
            participantInput: .init(
                outpointTransactionHashBytes: [UInt8](transactionHash.reverseOrder),
                outpointIndex: outputIndex,
                amountSatoshis: participantAmountSatoshis ?? amountSatoshis,
                lockingScriptBytes: [UInt8](participantLockingScript ?? lockingScript),
                publicKey: [UInt8](signingKey.publicKey.compressedData)
            )
        )
    }

    static func makeScenario(
        materials suppliedMaterials: [InputMaterial]? = nil,
        transactionInputs: [OpalBase.Transaction.Input]? = nil,
        spentInputs: [OpalFusion.Host.ParticipantInput]? = nil,
        outputs suppliedOutputs: [OpalBase.Transaction.Output]? = nil,
        version: UInt32 = 2,
        lockTime: UInt32 = 0,
        profile: OpalFusion.Mosaic.Profile = .opalV0,
        feeRateSatoshisPerByte: UInt64 = 1,
        minimumExcessFeeSatoshis: UInt64 = 0,
        maximumExcessFeeSatoshis: UInt64 = 0,
        transactionProfileIdentifier: String? = nil,
        transactionReader suppliedReader: OpalBase.Network.TransactionReader? = nil
    ) throws -> Scenario {
        let materials = try suppliedMaterials ?? [makeInputMaterial()]
        let inputs = transactionInputs ?? materials.map(\.transactionInput)
        let participantInputs = spentInputs ?? materials.map(\.participantInput)
        let outputs: [OpalBase.Transaction.Output]
        if let suppliedOutputs {
            outputs = suppliedOutputs
        } else {
            let lockingScript = try makeP2PKHLockingScript(seed: 0x20)
            let template = OpalBase.Transaction(
                version: version,
                inputs: inputs,
                outputs: [.init(value: 1, lockingScript: lockingScript)],
                lockTime: lockTime
            )
            let expectedFee = try template.calculateFee(feePerByte: 1)
            let inputValue = participantInputs.reduce(UInt64(0)) {
                $0 + $1.amountSatoshis
            }
            outputs = [
                .init(
                    value: inputValue - expectedFee,
                    lockingScript: lockingScript
                )
            ]
        }

        let transaction = OpalBase.Transaction(
            version: version,
            inputs: inputs,
            outputs: outputs,
            lockTime: lockTime
        )
        let unsignedTransactionBytes = [UInt8](try transaction.encode())
        let transcriptBinding = try MosaicHostFixture.makeTranscriptBinding(
            profile: profile,
            unsignedTransactionBytes: unsignedTransactionBytes,
            discriminator: 0x55
        )
        let request = try OpalFusion.Host.MosaicTransactionSigningRequest(
            reservationReference: .init(identifier: UUID(), generation: 1),
            roundIdentifier: Array(repeating: 0x33, count: 32),
            transcriptBinding: transcriptBinding,
            unsignedTransactionBytes: unsignedTransactionBytes,
            spentInputs: participantInputs,
            localInputIndices: [0],
            expectedLocalOutputs: [
                .init(
                    lockingScriptBytes: [UInt8](outputs[0].lockingScript),
                    amountSatoshis: outputs[0].value
                )
            ],
            feeRateSatoshisPerByte: feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis: minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: maximumExcessFeeSatoshis,
            transactionProfileIdentifier: transactionProfileIdentifier
                ?? profile.transactionProfileIdentifier
        )
        let rawTransactions = Dictionary(
            uniqueKeysWithValues: materials.map {
                ($0.transactionHash, $0.rawPreviousTransaction)
            }
        )
        let transactionReader = suppliedReader ?? .init { transactionHash in
            guard let rawTransaction = rawTransactions[transactionHash] else {
                throw FixtureFailure.missingPreviousTransaction
            }
            return rawTransaction
        }
        let inputValue = participantInputs.reduce(UInt64(0)) {
            $0 + $1.amountSatoshis
        }
        let outputValue = outputs.reduce(UInt64(0)) { $0 + $1.value }
        return .init(
            policy: try .init(network: .chipnet, transactionReader: transactionReader),
            transaction: transaction,
            request: request,
            feeSatoshis: inputValue >= outputValue ? inputValue - outputValue : 0
        )
    }

    static func makeP2PKHLockingScript(seed: UInt8) throws -> Data {
        let signingKey = try OpalBase.Key.SigningKey(
            rawRepresentation: Data(repeating: seed, count: 32)
        )
        return OpalBase.Script.p2pkh_OPCHECKSIG(
            hash: .init(publicKey: signingKey.publicKey)
        ).data
    }

    enum FixtureFailure: Swift.Error {
        case missingPreviousTransaction
        case unavailable
    }
}
#endif
