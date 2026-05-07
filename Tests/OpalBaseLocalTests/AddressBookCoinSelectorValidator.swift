// AddressBookCoinSelectorValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Address.Book Coin Selector", .tags(.unit, .address))
struct AddressBookCoinSelectorValidator {
    @Test("select greedy throws when summing unspent outputs overflows UInt64")
    func selectGreedyDetectsOverflow1() {
        let previousTransactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        let lockingScript = Data([0x51])

        let firstUnspent = OpalBase.Transaction.Output.Unspent(
            value: UInt64.max &- 1,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )

        let secondUnspent = OpalBase.Transaction.Output.Unspent(
            value: 10,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 1
        )

        let configuration = OpalBase.Address.Book.CoinSelection.Configuration(
            recipientOutputs: OpalBase.Address.Book.CoinSelection.Templates.recipientOutputs,
            outputsWithChange: OpalBase.Address.Book.CoinSelection.Templates.outputsWithChange,
            strategy: .greedyLargestFirst
        )

        let selector = OpalBase.Address.Book.CoinSelector(
            utxos: [firstUnspent, secondUnspent],
            configuration: configuration,
            targetAmount: UInt64.max,
            feePerByte: 0,
            minimumRelayFeeRate: 0
        )

        #expect(throws: OpalBase.Address.Book.Error.paymentExceedsMaximumAmount) {
            _ = try selector.select()
        }
    }

    @Test("select throws when the accumulated value exceeds the maximum amount")
    func selectGreedyDetectsOverflow2() throws {
        let lockingScript = Data(repeating: 0, count: 25)
        let placeholderHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))

        let nearMaximumUnspent = OpalBase.Transaction.Output.Unspent(
            value: UInt64.max - 1,
            lockingScript: lockingScript,
            previousTransactionHash: placeholderHash,
            previousTransactionOutputIndex: 0
        )

        let smallUnspent = OpalBase.Transaction.Output.Unspent(
            value: 2,
            lockingScript: lockingScript,
            previousTransactionHash: placeholderHash,
            previousTransactionOutputIndex: 1
        )

        let selector = OpalBase.Address.Book.CoinSelector(
            utxos: [nearMaximumUnspent, smallUnspent],
            configuration: .makeTemplateConfiguration(strategy: .greedyLargestFirst),
            targetAmount: UInt64.max,
            feePerByte: 0,
            minimumRelayFeeRate: 0
        )

        #expect(throws: OpalBase.Address.Book.Error.paymentExceedsMaximumAmount) {
            _ = try selector.select()
        }
    }

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
            recipientOutputs: recipientOutputs,
            outputsWithChange: outputsWithChange,
            minimumRelayFeeRate: 1,
            feePerByte: 1
        )

        #expect(evaluation == nil)
    }
}
