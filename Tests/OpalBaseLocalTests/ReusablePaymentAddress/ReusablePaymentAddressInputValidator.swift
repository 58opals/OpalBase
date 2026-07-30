// ReusablePaymentAddressInputValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Reusable payment address input qualification", .tags(.unit))
struct ReusablePaymentAddressInputValidator {
    @Test("positive vector derives exact filter prefix and serialized-input digest")
    func qualifyExactPositiveInput() throws {
        let decoded = try ReusablePaymentAddressFixtureData.decodeTransaction(
            hexadecimalString:
                ReusablePaymentAddressFixtureData.positiveTransactionHex
        )
        let transaction = decoded.transaction
        let input = try #require(transaction.inputs.first)
        let cashCode = try ReusablePaymentAddressFixtureData.makeAddress()
        let qualifyingInputs = CashCodeQualifyingInput.collect(
            from: transaction
        )

        #expect(decoded.bytesRead == 254)
        #expect(decoded.bytesRead == decoded.data.count)
        #expect(cashCode.filterPrefix.bitCount == 16)
        #expect(cashCode.filterPrefix.hexadecimalString == "5cbd")
        #expect(cashCode.filterPrefix.matches(input))
        #expect(
            OpalCryptoAdapter.hash256(input.encode()).hexadecimalString
                == "5cbd74af4d7f627168c121e5472a1664f96e6beedf6bc133eedf65d2db11c1b5"
        )
        #expect(qualifyingInputs.count == 1)
        #expect(qualifyingInputs[0].index == 0)
        #expect(
            qualifyingInputs[0].publicKey.compressedData.hexadecimalString
                == ReusablePaymentAddressFixtureData.senderCompressedPublicKey
        )
    }

    @Test("valid compressed P2PKH input remains a candidate when its prefix misses")
    func rejectPrefixMissAfterQualification() throws {
        let decoded = try ReusablePaymentAddressFixtureData.decodeTransaction(
            hexadecimalString:
                ReusablePaymentAddressFixtureData.prefixMissTransactionHex
        )
        let input = try #require(decoded.transaction.inputs.first)
        let cashCode = try ReusablePaymentAddressFixtureData.makeAddress()

        #expect(
            OpalCryptoAdapter.hash256(input.encode()).hexadecimalString
                == "f414666b5346fd69315abcdcd125588dee07a22ebd1970a31d1e504f25133433"
        )
        #expect(
            CashCodeQualifyingInput.collect(
                from: decoded.transaction
            ).count == 1
        )
        #expect(!cashCode.filterPrefix.matches(input))
    }

    @Test("valid uncompressed P2PKH input is outside Cash Code v1")
    func rejectUncompressedInputKey() throws {
        let decoded = try ReusablePaymentAddressFixtureData.decodeTransaction(
            hexadecimalString:
                ReusablePaymentAddressFixtureData
                    .uncompressedInputTransactionHex
        )

        #expect(decoded.bytesRead == decoded.data.count)
        #expect(
            CashCodeQualifyingInput.collect(
                from: decoded.transaction
            ).isEmpty
        )
    }

    @Test("coinbase and noncanonical P2PKH unlocking bytecode are not candidates")
    func rejectCoinbaseAndNoncanonicalUnlockingBytecode() throws {
        let transaction = try ReusablePaymentAddressFixtureData
            .decodeTransaction(
                hexadecimalString:
                    ReusablePaymentAddressFixtureData
                        .positiveTransactionHex
            ).transaction
        let input = try #require(transaction.inputs.first)
        let coinbase = OpalBase.Transaction.Input(
            previousTransactionHash: .init(
                naturalOrder: Data(repeating: 0, count: 32)
            ),
            previousTransactionOutputIndex: UInt32.max,
            unlockingScript: input.unlockingScript,
            sequence: input.sequence
        )
        let trailingByte = OpalBase.Transaction.Input(
            previousTransactionHash: input.previousTransactionHash,
            previousTransactionOutputIndex:
                input.previousTransactionOutputIndex,
            unlockingScript: input.unlockingScript + Data([0]),
            sequence: input.sequence
        )
        var invalidHashTypeScript = input.unlockingScript
        invalidHashTypeScript[65] = 0x01
        let invalidHashType = OpalBase.Transaction.Input(
            previousTransactionHash: input.previousTransactionHash,
            previousTransactionOutputIndex:
                input.previousTransactionOutputIndex,
            unlockingScript: invalidHashTypeScript,
            sequence: input.sequence
        )

        for rejectedInput in [coinbase, trailingByte, invalidHashType] {
            #expect(
                CashCodeQualifyingInput.collect(
                    from: OpalBase.Transaction(
                        version: transaction.version,
                        inputs: [rejectedInput],
                        outputs: transaction.outputs,
                        lockTime: transaction.lockTime
                    )
                ).isEmpty
            )
        }
    }

    @Test("strict DER and Schnorr P2PKH shapes both qualify")
    func acceptSupportedSignatureShapes() throws {
        let transaction = try ReusablePaymentAddressFixtureData
            .decodeTransaction(
                hexadecimalString:
                    ReusablePaymentAddressFixtureData
                        .positiveTransactionHex
            ).transaction
        let schnorrInput = try #require(transaction.inputs.first)
        let derSignatureWithHashType = Data([
            0x30, 0x06,
            0x02, 0x01, 0x01,
            0x02, 0x01, 0x01,
            0x41,
        ])
        let derUnlockingScript =
            Data([UInt8(derSignatureWithHashType.count)])
            + derSignatureWithHashType
            + Data([33])
            + schnorrInput.unlockingScript.suffix(33)
        let derInput = OpalBase.Transaction.Input(
            previousTransactionHash:
                schnorrInput.previousTransactionHash,
            previousTransactionOutputIndex:
                schnorrInput.previousTransactionOutputIndex,
            unlockingScript: derUnlockingScript,
            sequence: schnorrInput.sequence
        )

        let qualifyingInputs = CashCodeQualifyingInput.collect(
            from: OpalBase.Transaction(
                version: transaction.version,
                inputs: [schnorrInput, derInput],
                outputs: transaction.outputs,
                lockTime: transaction.lockTime
            )
        )

        #expect(qualifyingInputs.map(\.index) == [0, 1])
    }

    @Test("input qualification is limited to zero-based indices 0 through 29")
    func enforceFirstThirtyInputLimit() throws {
        let positive = try ReusablePaymentAddressFixtureData
            .decodeTransaction(
                hexadecimalString:
                    ReusablePaymentAddressFixtureData
                        .positiveTransactionHex
            ).transaction
        let prefixMiss = try ReusablePaymentAddressFixtureData
            .decodeTransaction(
                hexadecimalString:
                    ReusablePaymentAddressFixtureData
                        .prefixMissTransactionHex
            ).transaction
        let positiveInput = try #require(positive.inputs.first)
        let prefixMissInput = try #require(prefixMiss.inputs.first)
        let transaction = OpalBase.Transaction(
            version: positive.version,
            inputs: Array(
                repeating: prefixMissInput,
                count: CashCodeQualifyingInput.maximumInputCount
            ) + [positiveInput],
            outputs: positive.outputs,
            lockTime: positive.lockTime
        )
        let cashCode = try ReusablePaymentAddressFixtureData.makeAddress()
        let qualifyingInputs = CashCodeQualifyingInput.collect(
            from: transaction
        )

        #expect(qualifyingInputs.count == 30)
        #expect(qualifyingInputs.last?.index == 29)
        #expect(
            qualifyingInputs.allSatisfy {
                !cashCode.filterPrefix.matches($0.input)
            }
        )
    }
}
