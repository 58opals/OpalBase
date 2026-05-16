// AddressBookCoinSelectorValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Address.Book Coin Selector", .tags(.unit, .address))
struct AddressBookCoinSelectorValidator {
    @Test("select throws when utxo accumulation overflows UInt64")
    func selectGreedyThrowsOnOverflow() async throws {
        let previousTransactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        let utxoWithMaximumValue = OpalBase.Transaction.Output.Unspent(
            value: UInt64.max - 1,
            lockingScript: Data(),
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        let utxoTriggeringOverflow = OpalBase.Transaction.Output.Unspent(
            value: 10,
            lockingScript: Data(),
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 1
        )

        let configuration = OpalBase.Address.Book.CoinSelection.Configuration.makeTemplateConfiguration(strategy: .greedyLargestFirst)
        let coinSelector = OpalBase.Address.Book.CoinSelector(
            utxos: [utxoWithMaximumValue, utxoTriggeringOverflow],
            configuration: configuration,
            targetAmount: UInt64.max,
            feePerByte: 0,
            minimumRelayFeeRate: 0
        )

        #expect(throws: OpalBase.Address.Book.Error.paymentExceedsMaximumAmount) {
            _ = try coinSelector.select()
        }
    }

    @Test("evaluation rejects dust donation for token change outputs")
    func evaluationRejectsDustDonationForTokenChangeOutputs() throws {
        let recipientOutputs = [
            OpalBase.Transaction.Output(value: 1_000, lockingScript: Data([0x51]))
        ]
        let tokenChangeOutput = OpalBase.Transaction.Output(
            value: 0,
            lockingScript: Data([0x52]),
            tokenData: try AddressBookCashTokensTestData.makeTokenData()
        )
        let outputsWithChange = recipientOutputs + [tokenChangeOutput]
        let configuration = OpalBase.Address.Book.CoinSelection.Configuration(
            recipientOutputs: recipientOutputs,
            outputsWithChange: outputsWithChange,
            strategy: .greedyLargestFirst,
            shouldAllowDustDonation: true,
            tokenSelectionPolicy: .allowTokenUTXOs
        )
        let feeWithoutChange = try OpalBase.Transaction.estimateFee(
            inputCount: 1,
            outputs: recipientOutputs,
            feePerByte: 1
        )

        let evaluation = try OpalBase.Address.Book.CoinSelection.evaluate(
            configuration: configuration,
            total: 1_000 + feeWithoutChange + 100,
            inputCount: 1,
            targetAmount: 1_000,
            minimumRelayFeeRate: 1,
            feePerByte: 1
        )

        #expect(evaluation == nil)
    }

    @Test("evaluation rejects excess without a change output")
    func evaluationRejectsExcessWithoutChangeOutput() throws {
        let recipientOutputs = [
            OpalBase.Transaction.Output(value: 1_000, lockingScript: Data([0x51]))
        ]
        let configuration = OpalBase.Address.Book.CoinSelection.Configuration(
            recipientOutputs: recipientOutputs,
            changeLockingScript: nil,
            strategy: .greedyLargestFirst,
            shouldAllowDustDonation: false
        )
        let feeWithoutChange = try OpalBase.Transaction.estimateFee(
            inputCount: 1,
            outputs: recipientOutputs,
            feePerByte: 1
        )

        let evaluation = try OpalBase.Address.Book.CoinSelection.evaluate(
            configuration: configuration,
            total: 1_000 + feeWithoutChange + 1,
            inputCount: 1,
            targetAmount: 1_000,
            minimumRelayFeeRate: 1,
            feePerByte: 1
        )

        #expect(evaluation == nil)
    }
}
