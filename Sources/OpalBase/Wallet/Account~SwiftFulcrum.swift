// Account~SwiftFulcrum.swift

import Foundation
import SwiftFulcrum

extension Account {
    public func calculateBalance() async throws -> Satoshi {
        var totalBalance: UInt64 = 0
        
        for address in await (addressBook.receivingEntries + addressBook.changeEntries).map({ $0.address }) {
            totalBalance += try await addressBook.getBalanceFromBlockchain(address: address, fulcrum: fulcrumPool.getFulcrum()).uint64
        }
        
        return try Satoshi(totalBalance)
    }
    
    public func send(_ sendings: [(value: Satoshi, recipientAddress: Address)]) async throws -> Data {
        let accountBalance = try await calculateBalance()
        let spendingValue = sendings.map{ $0.value.uint64 }.reduce(0, +)
        guard spendingValue < accountBalance.uint64 else { throw Transaction.Error.insufficientFunds(required: spendingValue) }
        
        let utxos = try await addressBook.selectUTXOs(targetAmount: Satoshi(spendingValue))
        let spendableValue = utxos.map { $0.value }.reduce(0, +)
        
        let privateKeyPairs = try await addressBook.getPrivateKeys(for: utxos)
        
        let changeAddress = try await addressBook.getNextEntry(for: .change).address
        let remainingValue = spendableValue - spendingValue
        
        let transaction = try Transaction.createTransaction(version: 2,
                                                            utxoPrivateKeyPairs: privateKeyPairs,
                                                            recipientOutputs: sendings.map { Transaction.Output(value: $0.value.uint64, address: $0.recipientAddress) },
                                                            changeOutput: Transaction.Output(value: remainingValue, address: changeAddress),
                                                            feePerByte: Transaction.defaultFeeRate)
        
        let broadcastRequest = { [self] in
            let fulcrum = try await fulcrumPool.getFulcrum()
            let response = try await transaction.broadcast(using: fulcrum)
            guard !response.isEmpty else { throw Transaction.Error.cannotBroadcastTransaction }
        }
        
        if await fulcrumPool.currentStatus == .online {
            do { try await broadcastRequest() }
            catch { enqueueRequest(broadcastRequest) }
        } else {
            enqueueRequest(broadcastRequest)
        }
        
        let manuallyGeneratedTransactionHash = Transaction.Hash(naturalOrder: HASH256.hash(transaction.encode()))
        
        await addressBook.handleOutgoingTransaction(transaction)
        
        return manuallyGeneratedTransactionHash.naturalOrder
    }
    
    public func refreshUTXOSet() async {
        let request = { [self] in
            let fulcrum = try await self.fulcrumPool.getFulcrum()
            try await self.addressBook.refreshUTXOSet(fulcrum: fulcrum)
        }
        
        do { try await request() }
        catch { enqueueRequest(request) }
    }
}
