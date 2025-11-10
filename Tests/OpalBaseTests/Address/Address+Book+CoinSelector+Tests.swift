import Foundation
import Testing
@testable import OpalBase

@Suite("Address Book Coin Selector", .tags(.unit, .address))
struct AddressBookCoinSelectorTests {
    @Test("select greedy throws when summing unspent outputs overflows UInt64")
    func testSelectGreedyDetectsOverflow1() {
        let previousTransactionHash = Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        let lockingScript = Data([0x51])
        
        let firstUnspent = Transaction.Output.Unspent(
            value: UInt64.max &- 1,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        
        let secondUnspent = Transaction.Output.Unspent(
            value: 10,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 1
        )
        
        let configuration = Address.Book.CoinSelection.Configuration(
            recipientOutputs: [],
            outputsWithChange: [],
            strategy: .greedyLargestFirst
        )
        
        let selector = Address.Book.CoinSelector(
            utxos: [firstUnspent, secondUnspent],
            configuration: configuration,
            targetAmount: UInt64.max,
            feePerByte: 0,
            dustLimit: 0
        )
        
        #expect(throws: Address.Book.Error.paymentExceedsMaximumAmount) {
            _ = try selector.select()
        }
    }
    
    @Test("select throws when the accumulated value exceeds the maximum amount")
    func testSelectGreedyDetectsOverflow2() throws {
        let lockingScript = Data(repeating: 0, count: 25)
        let placeholderHash = Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        
        let nearMaximumUnspent = Transaction.Output.Unspent(
            value: UInt64.max - 1,
            lockingScript: lockingScript,
            previousTransactionHash: placeholderHash,
            previousTransactionOutputIndex: 0
        )
        
        let smallUnspent = Transaction.Output.Unspent(
            value: 2,
            lockingScript: lockingScript,
            previousTransactionHash: placeholderHash,
            previousTransactionOutputIndex: 1
        )
        
        let selector = Address.Book.CoinSelector(
            utxos: [nearMaximumUnspent, smallUnspent],
            configuration: .makeTemplateConfiguration(strategy: .greedyLargestFirst),
            targetAmount: UInt64.max,
            feePerByte: 0,
            dustLimit: 0
        )
        
        #expect(throws: Address.Book.Error.paymentExceedsMaximumAmount) {
            _ = try selector.select()
        }
    }
    
    @Test("select throws when utxo accumulation overflows UInt64")
    func testSelectGreedyThrowsOnOverflow() async throws {
        let previousTransactionHash = Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        let utxoWithMaximumValue = Transaction.Output.Unspent(
            value: UInt64.max - 1,
            lockingScript: Data(),
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        let utxoTriggeringOverflow = Transaction.Output.Unspent(
            value: 10,
            lockingScript: Data(),
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 1
        )
        
        let configuration = Address.Book.CoinSelection.Configuration.makeTemplateConfiguration(strategy: .greedyLargestFirst)
        let coinSelector = Address.Book.CoinSelector(
            utxos: [utxoWithMaximumValue, utxoTriggeringOverflow],
            configuration: configuration,
            targetAmount: UInt64.max,
            feePerByte: 0,
            dustLimit: 0
        )
        
        #expect(throws: Address.Book.Error.paymentExceedsMaximumAmount) {
            _ = try coinSelector.select()
        }
    }
}
