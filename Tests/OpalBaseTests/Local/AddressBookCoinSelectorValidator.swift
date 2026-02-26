import Foundation
import Testing
@testable import OpalBase

@Suite("AddressModel BookActor Coin Selector", .tags(.unit, .address))
struct AddressBookCoinSelectorValidator {
    @Test("select greedy throws when summing unspent outputs overflows UInt64")
    func selectGreedyDetectsOverflow1() {
        let previousTransactionHash = TransactionModel.HashModel(naturalOrder: Data(repeating: 0, count: 32))
        let lockingScript = Data([0x51])

        let firstUnspent = TransactionModel.OutputModel.UnspentModel(
            value: UInt64.max &- 1,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )

        let secondUnspent = TransactionModel.OutputModel.UnspentModel(
            value: 10,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 1
        )

        let configuration = AddressModel.BookActor.CoinSelectionModel.Configuration(
            recipientOutputs: .init(),
            outputsWithChange: .init(),
            strategy: .greedyLargestFirst
        )

        let selector = AddressModel.BookActor.CoinSelectorModel(
            utxos: [firstUnspent, secondUnspent],
            configuration: configuration,
            targetAmount: UInt64.max,
            feePerByte: 0,
            minimumRelayFeeRate: 0
        )

        #expect(throws: AddressModel.BookActor.Error.paymentExceedsMaximumAmount) {
            _ = try selector.select()
        }
    }

    @Test("select throws when the accumulated value exceeds the maximum amount")
    func selectGreedyDetectsOverflow2() throws {
        let lockingScript = Data(repeating: 0, count: 25)
        let placeholderHash = TransactionModel.HashModel(naturalOrder: Data(repeating: 0, count: 32))

        let nearMaximumUnspent = TransactionModel.OutputModel.UnspentModel(
            value: UInt64.max - 1,
            lockingScript: lockingScript,
            previousTransactionHash: placeholderHash,
            previousTransactionOutputIndex: 0
        )

        let smallUnspent = TransactionModel.OutputModel.UnspentModel(
            value: 2,
            lockingScript: lockingScript,
            previousTransactionHash: placeholderHash,
            previousTransactionOutputIndex: 1
        )

        let selector = AddressModel.BookActor.CoinSelectorModel(
            utxos: [nearMaximumUnspent, smallUnspent],
            configuration: .makeTemplateConfiguration(strategy: .greedyLargestFirst),
            targetAmount: UInt64.max,
            feePerByte: 0,
            minimumRelayFeeRate: 0
        )

        #expect(throws: AddressModel.BookActor.Error.paymentExceedsMaximumAmount) {
            _ = try selector.select()
        }
    }

    @Test("select throws when utxo accumulation overflows UInt64")
    func selectGreedyThrowsOnOverflow() async throws {
        let previousTransactionHash = TransactionModel.HashModel(naturalOrder: Data(repeating: 0, count: 32))
        let utxoWithMaximumValue = TransactionModel.OutputModel.UnspentModel(
            value: UInt64.max - 1,
            lockingScript: Data(),
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        let utxoTriggeringOverflow = TransactionModel.OutputModel.UnspentModel(
            value: 10,
            lockingScript: Data(),
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 1
        )

        let configuration = AddressModel.BookActor.CoinSelectionModel.Configuration.makeTemplateConfiguration(strategy: .greedyLargestFirst)
        let coinSelector = AddressModel.BookActor.CoinSelectorModel(
            utxos: [utxoWithMaximumValue, utxoTriggeringOverflow],
            configuration: configuration,
            targetAmount: UInt64.max,
            feePerByte: 0,
            minimumRelayFeeRate: 0
        )

        #expect(throws: AddressModel.BookActor.Error.paymentExceedsMaximumAmount) {
            _ = try coinSelector.select()
        }
    }
}
