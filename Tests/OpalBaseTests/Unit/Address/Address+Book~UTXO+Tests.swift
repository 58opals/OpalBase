import Foundation
import Testing
@testable import OpalBase

@Suite("Address Book UTXO Selection", .tags(.unit, .wallet))
struct AddressBookUTXOSuite {
    private func makeAddressBook() async throws -> Address.Book {
        let mnemonic = try Mnemonic(words: [
            "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
            "abandon", "abandon", "abandon", "abandon", "abandon", "about"
        ])
        let rootKey = PrivateKey.Extended(rootKey: try .init(seed: mnemonic.seed))
        let account = try DerivationPath.Account(rawIndexInteger: 0)
        
        return try await Address.Book(
            rootExtendedPrivateKey: rootKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: account,
            gapLimit: 1,
            cacheValidityDuration: 60
        )
    }
    
    @Test("greedy largest-first does not double-count fees", .tags(.unit, .wallet))
    func greedySelectionDoesNotDoubleCountFees() async throws {
        let subject = try await makeAddressBook()
        
        let hash = Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        let highValue = Transaction.Output.Unspent(
            value: 5_000,
            lockingScript: Data(),
            previousTransactionHash: hash,
            previousTransactionOutputIndex: 0
        )
        let topUp = Transaction.Output.Unspent(
            value: 500,
            lockingScript: Data(),
            previousTransactionHash: hash,
            previousTransactionOutputIndex: 1
        )
        
        await subject.addUTXOs([highValue, topUp])
        
        let selection = try await subject.selectUTXOs(
            targetAmount: try Satoshi(5_000),
            feePerByte: 1,
            strategy: .greedyLargestFirst
        )
        
        #expect(Set(selection) == Set([highValue, topUp]))
    }
    
    @Test("greedy largest-first succeeds when total equals amount plus fee", .tags(.unit, .wallet))
    func greedySelectionAcceptsExactAmountPlusFee() async throws {
        let subject = try await makeAddressBook()
        
        let hash = Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        let utxo = Transaction.Output.Unspent(
            value: 10_192,
            lockingScript: Data(),
            previousTransactionHash: hash,
            previousTransactionOutputIndex: 0
        )
        
        await subject.addUTXO(utxo)
        
        let selection = try await subject.selectUTXOs(
            targetAmount: try Satoshi(10_000),
            feePerByte: 1,
            strategy: .greedyLargestFirst
        )
        
        #expect(selection == [utxo])
    }
    
    @Test("branch and bound succeeds when total equals amount plus fee", .tags(.unit, .wallet))
    func branchAndBoundAcceptsExactAmountPlusFeeWithOutputs() async throws {
        let subject = try await makeAddressBook()
        let hash = Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        let lockingScript = Data([0x51])
        let recipient = Transaction.Output(value: 7_500, lockingScript: lockingScript)
        let fee = Transaction.estimatedFee(inputCount: 1,
                                           outputs: [recipient],
                                           feePerByte: 1)
        let targetAmount = try Satoshi(7_500)
        let utxo = Transaction.Output.Unspent(
            value: targetAmount.uint64 &+ fee,
            lockingScript: lockingScript,
            previousTransactionHash: hash,
            previousTransactionOutputIndex: 0
        )
        
        await subject.addUTXO(utxo)
        
        let greedySelection = try await subject.selectUTXOs(
            targetAmount: targetAmount,
            recipientOutputs: [recipient],
            changeLockingScript: lockingScript,
            feePerByte: 1,
            strategy: .greedyLargestFirst
        )
        
        #expect(greedySelection == [utxo])
        
        let selection = try await subject.selectUTXOs(
            targetAmount: targetAmount,
            recipientOutputs: [recipient],
            changeLockingScript: lockingScript,
            feePerByte: 1,
            strategy: .branchAndBound
        )
        
        #expect(selection == [utxo])
    }
}
