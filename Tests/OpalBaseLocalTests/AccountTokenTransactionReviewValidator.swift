// AccountTokenTransactionReviewValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Account token transaction review", .tags(.unit, .wallet, .cashTokens))
struct AccountTokenTransactionReviewValidator {
    @Test("token spend review initializer normalizes sliced raw transaction data")
    func tokenSpendReviewInitializerNormalizesSlicedRawTransactionData() throws {
        let rawTransactionData = Data([0x01, 0x02, 0x03])
        let paddedRawTransactionData = Data([0xff]) + rawTransactionData
        let slicedRawTransactionData = paddedRawTransactionData[
            paddedRawTransactionData.index(after: paddedRawTransactionData.startIndex)...
        ]

        let review = OpalBase.Account.TokenSpendPlan.Review(
            transaction: makeEmptyTransaction(),
            rawTransactionData: slicedRawTransactionData,
            rawTransactionByteCount: rawTransactionData.count,
            fee: try OpalBase.Satoshi(1),
            configuredFeeRate: 1,
            effectiveFeeRate: 1,
            bchChange: nil,
            tokenRecipientOutputs: [],
            tokenChangeOutputs: [],
            lockedBCHOutputValue: try OpalBase.Satoshi(0)
        )

        #expect(slicedRawTransactionData.startIndex != rawTransactionData.startIndex)
        #expect(review.rawTransactionData == rawTransactionData)
        #expect(review.rawTransactionData.startIndex == rawTransactionData.startIndex)
    }

    @Test("token genesis review initializer normalizes sliced raw transaction data")
    func tokenGenesisReviewInitializerNormalizesSlicedRawTransactionData() throws {
        let rawTransactionData = Data([0x04, 0x05, 0x06])
        let paddedRawTransactionData = Data([0xff]) + rawTransactionData
        let slicedRawTransactionData = paddedRawTransactionData[
            paddedRawTransactionData.index(after: paddedRawTransactionData.startIndex)...
        ]

        let review = OpalBase.Account.TokenGenesisPlan.Review(
            transaction: makeEmptyTransaction(),
            rawTransactionData: slicedRawTransactionData,
            rawTransactionByteCount: rawTransactionData.count,
            fee: try OpalBase.Satoshi(1),
            configuredFeeRate: 1,
            effectiveFeeRate: 1,
            category: try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0x11, count: 32)),
            mintedOutputs: [],
            bchChange: nil,
            lockedBCHOutputValue: try OpalBase.Satoshi(0),
            totalBCHNeeded: try OpalBase.Satoshi(1)
        )

        #expect(slicedRawTransactionData.startIndex != rawTransactionData.startIndex)
        #expect(review.rawTransactionData == rawTransactionData)
        #expect(review.rawTransactionData.startIndex == rawTransactionData.startIndex)
    }

    @Test("token output review initializer normalizes sliced locking script")
    func tokenOutputReviewInitializerNormalizesSlicedLockingScript() throws {
        let lockingScript = Data([0x51, 0x21, 0x00])
        let paddedLockingScript = Data([0xff]) + lockingScript
        let slicedLockingScript = paddedLockingScript[paddedLockingScript.index(after: paddedLockingScript.startIndex)...]

        let review = OpalBase.Account.TokenOutputReview(
            role: .recipient,
            value: try OpalBase.Satoshi(546),
            lockingScript: slicedLockingScript,
            tokenData: nil
        )

        #expect(slicedLockingScript.startIndex != lockingScript.startIndex)
        #expect(review.lockingScript == lockingScript)
        #expect(review.lockingScript.startIndex == lockingScript.startIndex)
    }

    private func makeEmptyTransaction() -> OpalBase.Transaction {
        OpalBase.Transaction(version: 2, inputs: [], outputs: [], lockTime: 0)
    }
}
