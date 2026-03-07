// AddressBookCoinSelectorValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Address BookActor Coin Selector", .tags(.unit, .address))
struct AddressBookCoinSelectorValidator {
    @Test("select greedy throws when summing unspent outputs overflows UInt64")
    func selectGreedyDetectsOverflow1() {
        let previousTransactionHash = OpalBase.Transaction.HashModel(naturalOrder: Data(repeating: 0, count: 32))
        let lockingScript = Data([0x51])

        let firstUnspent = OpalBase.Transaction.OutputModel.UnspentModel(
            value: UInt64.max &- 1,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )

        let secondUnspent = OpalBase.Transaction.OutputModel.UnspentModel(
            value: 10,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 1
        )

        let configuration = OpalBase.Address.Book.CoinSelectionModel.Configuration(
            recipientOutputs: .init(),
            outputsWithChange: .init(),
            strategy: .greedyLargestFirst
        )

        let selector = OpalBase.Address.Book.CoinSelectorModel(
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
        let placeholderHash = OpalBase.Transaction.HashModel(naturalOrder: Data(repeating: 0, count: 32))

        let nearMaximumUnspent = OpalBase.Transaction.OutputModel.UnspentModel(
            value: UInt64.max - 1,
            lockingScript: lockingScript,
            previousTransactionHash: placeholderHash,
            previousTransactionOutputIndex: 0
        )

        let smallUnspent = OpalBase.Transaction.OutputModel.UnspentModel(
            value: 2,
            lockingScript: lockingScript,
            previousTransactionHash: placeholderHash,
            previousTransactionOutputIndex: 1
        )

        let selector = OpalBase.Address.Book.CoinSelectorModel(
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
        let previousTransactionHash = OpalBase.Transaction.HashModel(naturalOrder: Data(repeating: 0, count: 32))
        let utxoWithMaximumValue = OpalBase.Transaction.OutputModel.UnspentModel(
            value: UInt64.max - 1,
            lockingScript: Data(),
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        let utxoTriggeringOverflow = OpalBase.Transaction.OutputModel.UnspentModel(
            value: 10,
            lockingScript: Data(),
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 1
        )

        let configuration = OpalBase.Address.Book.CoinSelectionModel.Configuration.makeTemplateConfiguration(strategy: .greedyLargestFirst)
        let coinSelector = OpalBase.Address.Book.CoinSelectorModel(
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
}

