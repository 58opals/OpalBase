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
    
    @Test("select branch and bound throws when minimal requirement overflows")
    func testSelectBranchAndBoundThrowsWhenMinimalRequirementOverflows() throws {
        let lockingScript = Data([0x51])
        let recipientOutputs = [Transaction.Output(value: 1, lockingScript: lockingScript)]
        let configuration = Address.Book.CoinSelection.Configuration(
            recipientOutputs: recipientOutputs,
            outputsWithChange: recipientOutputs,
            strategy: .branchAndBound
        )
        let feePerByte: UInt64 = 1
        let minimalFee = try Transaction.estimateFee(
            inputCount: 0,
            outputs: configuration.recipientOutputs,
            feePerByte: feePerByte
        )
        
        guard minimalFee > 0 else {
            Issue.record("Expected minimal fee to exceed zero for overflow scenario")
            return
        }
        
        let targetAmount = UInt64.max - (minimalFee - 1)
        let previousTransactionHash = Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        let largeUnspent = Transaction.Output.Unspent(
            value: UInt64.max,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        
        let coinSelector = Address.Book.CoinSelector(
            utxos: [largeUnspent],
            configuration: configuration,
            targetAmount: targetAmount,
            feePerByte: feePerByte,
            dustLimit: 0
        )
        
        #expect(throws: Address.Book.Error.paymentExceedsMaximumAmount) {
            _ = try coinSelector.select()
        }
    }
    
    @Test("select branch and bound throws when suffix totals overflow")
    func testSelectBranchAndBoundThrowsWhenSuffixTotalsOverflow() {
        let lockingScript = Data([0x51])
        let previousTransactionHash = Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        
        let nearMaximumUnspent = Transaction.Output.Unspent(
            value: UInt64.max,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        
        let smallUnspent = Transaction.Output.Unspent(
            value: 1,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 1
        )
        
        let configuration = Address.Book.CoinSelection.Configuration(
            recipientOutputs: [],
            outputsWithChange: [],
            strategy: .branchAndBound
        )
        
        let coinSelector = Address.Book.CoinSelector(
            utxos: [nearMaximumUnspent, smallUnspent],
            configuration: configuration,
            targetAmount: 0,
            feePerByte: 0,
            dustLimit: 0
        )
        
        #expect(throws: Address.Book.Error.paymentExceedsMaximumAmount) {
            _ = try coinSelector.select()
        }
    }
    
    @Test("branch and bound selection throws when suffix totals overflow UInt64")
    func testSelectBranchAndBoundDetectsSuffixOverflow() {
        let previousTransactionHash = Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        let lockingScript = Data([0x51])
        
        let minimalUnspent = Transaction.Output.Unspent(
            value: 1,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        
        let maximumUnspent = Transaction.Output.Unspent(
            value: UInt64.max,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 1
        )
        
        let configuration = Address.Book.CoinSelection.Configuration.makeTemplateConfiguration(strategy: .branchAndBound)
        
        let selector = Address.Book.CoinSelector(
            utxos: [minimalUnspent, maximumUnspent],
            configuration: configuration,
            targetAmount: UInt64.max,
            feePerByte: 0,
            dustLimit: 0
        )
        
        #expect(throws: Address.Book.Error.paymentExceedsMaximumAmount) {
            _ = try selector.select()
        }
    }
}
