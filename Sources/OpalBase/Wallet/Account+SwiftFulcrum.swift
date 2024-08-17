import Foundation
import SwiftFulcrum

extension Account {
    mutating func calculateBalance() async throws -> Satoshi {
        var totalBalance: UInt64 = 0
        
        for address in (addressBook.receivingEntries + addressBook.changeEntries).map({ $0.address }) {
            totalBalance += try await addressBook.getBalance(for: address, updateCacheBalance: true).uint64
        }
        
        return try Satoshi(totalBalance)
    }
    
    mutating func send(_ sendings: [(value: Satoshi, recipientAddress: Address)]) async throws -> Data {
        let accountBalance = try await calculateBalance()
        let spendingValue = sendings.map{ $0.value.uint64 }.reduce(0, +)
        guard spendingValue < accountBalance.uint64 else { throw Transaction.Error.insufficientFunds(required: spendingValue) }
        
        let utxos = try addressBook.selectUTXOs(targetAmount: Satoshi(spendingValue))
        let spendableValue = utxos.map { $0.value }.reduce(0, +)
        
        
        
        let privateKeyPairs = try addressBook.getPrivateKeys(for: utxos)
        
        let changeAddress = try await addressBook.getNextEntry(for: .change).address
        let remainingValue = spendableValue - spendingValue
        
        let transaction = try Transaction.createTransaction(version: 2,
                                                            utxoPrivateKeyPairs: privateKeyPairs,
                                                            recipientOutputs: sendings.map { Transaction.Output(value: $0.value.uint64, address: $0.recipientAddress) },
                                                            changeOutput: Transaction.Output(value: remainingValue, address: changeAddress),
                                                            feePerByte: Transaction.defaultFeeRate)
        
        let transactionHashFromFulcrum = try await transaction.broadcast(using: fulcrum)
        guard !transactionHashFromFulcrum.isEmpty else { throw Transaction.Error.cannotBroadcastTransaction }
        let manuallyGeneratedTransactionHash = Transaction.Hash(naturalOrder: HASH256.hash(transaction.encode()))
        
        addressBook.handleOutgoingTransaction(transaction)
        
        return manuallyGeneratedTransactionHash.naturalOrder
    }
}
