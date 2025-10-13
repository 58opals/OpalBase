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
    
    @Test("greedy largest-first accounts for change cost at elevated fee rates", .tags(.unit, .wallet))
    func greedySelectionRespectsChangeFeesAtHighRates() async throws {
        let subject = try await makeAddressBook()
        let hash = Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        
        let primary = Transaction.Output.Unspent(
            value: 30_000,
            lockingScript: Data(),
            previousTransactionHash: hash,
            previousTransactionOutputIndex: 0
        )
        let secondary = Transaction.Output.Unspent(
            value: 27_400,
            lockingScript: Data(),
            previousTransactionHash: hash,
            previousTransactionOutputIndex: 1
        )
        let buffer = Transaction.Output.Unspent(
            value: 4_000,
            lockingScript: Data(),
            previousTransactionHash: hash,
            previousTransactionOutputIndex: 2
        )
        
        await subject.addUTXOs([primary, secondary, buffer])
        
        let feePerByte: UInt64 = 20
        let target = try Satoshi(50_000)
        let selection = try await subject.selectUTXOs(
            targetAmount: target,
            feePerByte: feePerByte,
            strategy: .greedyLargestFirst
        )
        
        #expect(Set(selection) == Set([primary, secondary, buffer]))
        
        let total = selection.reduce(UInt64(0)) { $0 &+ $1.value }
        let placeholderScript = Data(repeating: 0, count: 25)
        let outputsWithChange = [
            Transaction.Output(value: 0, lockingScript: placeholderScript),
            Transaction.Output(value: 0, lockingScript: placeholderScript)
        ]
        let feeWithChange = Transaction.estimatedFee(
            inputCount: selection.count,
            outputs: outputsWithChange,
            feePerByte: feePerByte
        )
        
        #expect(total >= target.uint64 &+ feeWithChange)
        let change = total &- target.uint64 &- feeWithChange
        #expect(change >= Transaction.dustLimit)
    }
    
    @Test("branch and bound accounts for change cost at elevated fee rates", .tags(.unit, .wallet))
    func branchAndBoundSelectionRespectsChangeFeesAtHighRates() async throws {
        let subject = try await makeAddressBook()
        let hash = Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        
        let primary = Transaction.Output.Unspent(
            value: 30_000,
            lockingScript: Data(),
            previousTransactionHash: hash,
            previousTransactionOutputIndex: 0
        )
        let secondary = Transaction.Output.Unspent(
            value: 27_400,
            lockingScript: Data(),
            previousTransactionHash: hash,
            previousTransactionOutputIndex: 1
        )
        let buffer = Transaction.Output.Unspent(
            value: 4_000,
            lockingScript: Data(),
            previousTransactionHash: hash,
            previousTransactionOutputIndex: 2
        )
        
        await subject.addUTXOs([primary, secondary, buffer])
        
        let feePerByte: UInt64 = 20
        let target = try Satoshi(50_000)
        let selection = try await subject.selectUTXOs(
            targetAmount: target,
            feePerByte: feePerByte,
            strategy: .branchAndBound
        )
        
        #expect(Set(selection) == Set([primary, secondary, buffer]))
        
        let total = selection.reduce(UInt64(0)) { $0 &+ $1.value }
        let placeholderScript = Data(repeating: 0, count: 25)
        let outputsWithChange = [
            Transaction.Output(value: 0, lockingScript: placeholderScript),
            Transaction.Output(value: 0, lockingScript: placeholderScript)
        ]
        let feeWithChange = Transaction.estimatedFee(
            inputCount: selection.count,
            outputs: outputsWithChange,
            feePerByte: feePerByte
        )
        
        #expect(total >= target.uint64 &+ feeWithChange)
        let change = total &- target.uint64 &- feeWithChange
        #expect(change >= Transaction.dustLimit)
    }
    
    @Test("incoming transactions preserve natural-order hashes", .tags(.unit, .wallet))
    func incomingTransactionsPreserveNaturalOrderHashes() async throws {
        let subject = try await makeAddressBook()
        let receivingEntry = try await subject.selectNextEntry(for: .receiving)
        
        let receivedValue: UInt64 = 12_500
        let receivingOutput = Transaction.Output(value: receivedValue, address: receivingEntry.address)
        
        let fundingInput = Transaction.Input(
            previousTransactionHash: .init(naturalOrder: Data(repeating: 0xAB, count: 32)),
            previousTransactionOutputIndex: 1,
            unlockingScript: Data(),
            sequence: 0xFFFF_FFFF
        )
        
        let incomingTransaction = Transaction(
            version: 2,
            inputs: [fundingInput],
            outputs: [receivingOutput],
            lockTime: 0
        )
        
        let transactionHash = Transaction.Hash(naturalOrder: Data((0..<32).map(UInt8.init)))
        let encodedIncomingTransaction = incomingTransaction.encode()
        
        let detailedTransaction = Transaction.Detailed(
            transaction: incomingTransaction,
            blockHash: nil,
            blockTime: nil,
            confirmations: nil,
            hash: transactionHash,
            raw: encodedIncomingTransaction,
            size: UInt32(encodedIncomingTransaction.count),
            time: nil
        )
        
        try await subject.handleIncomingTransaction(detailedTransaction)
        
        let expectedUTXO = Transaction.Output.Unspent(
            output: receivingOutput,
            previousTransactionHash: transactionHash,
            previousTransactionOutputIndex: 0
        )
        
        let utxos = await subject.listUTXOs()
        #expect(utxos.contains(expectedUTXO))
        
        let spendingInput = Transaction.Input(
            previousTransactionHash: transactionHash,
            previousTransactionOutputIndex: 0,
            unlockingScript: Data(),
            sequence: 0xFFFF_FFFF
        )
        
        let spendingTransaction = Transaction(
            version: 2,
            inputs: [spendingInput],
            outputs: [Transaction.Output(value: receivedValue &- 500, lockingScript: Data())],
            lockTime: 0
        )
        
        await subject.handleOutgoingTransaction(spendingTransaction)
        
        let remainingUTXOs = await subject.listUTXOs()
        #expect(remainingUTXOs.isEmpty)
    }
}
