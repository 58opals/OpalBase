// Account~SwiftFulcrum.swift

import Foundation
import SwiftFulcrum

extension Account {
    public func calculateBalance() async throws -> Satoshi {
        let addresses = await (addressBook.receivingEntries + addressBook.changeEntries).map { $0.address }
        guard !addresses.isEmpty else { return try Satoshi(0) }
        
        let fulcrum = try await fulcrumPool.getFulcrum()
        let total = try await withThrowingTaskGroup(of: UInt64.self) { group in
            for address in addresses {
                group.addTask {
                    let balance = try await self.addressBook.getBalanceFromBlockchain(address: address, fulcrum: fulcrum)
                    return balance.uint64
                }
            }
            
            var aggregate: UInt64 = 0
            for try await partial in group { aggregate += partial }
            return aggregate
        }
        
        return try Satoshi(total)
    }
    
    public func send(_ sendings: [(value: Satoshi, recipientAddress: Address)],
                     feePerByte: UInt64? = nil,
                     allowDustDonation: Bool = false,
                     strategy: Address.Book.CoinSelection = .greedyLargestFirst) async throws -> Data {
        let accountBalance = try await calculateBalance()
        let spendingValue = sendings.map{ $0.value.uint64 }.reduce(0, +)
        guard spendingValue < accountBalance.uint64 else { throw Transaction.Error.insufficientFunds(required: spendingValue) }
        
        var selectedFeeRate: UInt64
        if let feePerByte = feePerByte {
            selectedFeeRate = feePerByte
        } else {
            selectedFeeRate = try await feeRate.getRecommendedFeeRate()
        }
        
        let utxos = try await addressBook.selectUTXOs(targetAmount: Satoshi(spendingValue), feePerByte: selectedFeeRate, strategy: strategy)
        let spendableValue = utxos.map { $0.value }.reduce(0, +)
        
        let privateKeyPairs = try await addressBook.getPrivateKeys(for: utxos)
        
        let changeAddress = try await addressBook.getNextEntry(for: .change).address
        let remainingValue = spendableValue - spendingValue
        
        let transaction = try Transaction.createTransaction(version: 2,
                                                            utxoPrivateKeyPairs: privateKeyPairs,
                                                            recipientOutputs: sendings.map { Transaction.Output(value: $0.value.uint64, address: $0.recipientAddress) },
                                                            changeOutput: Transaction.Output(value: remainingValue, address: changeAddress),
                                                            feePerByte: selectedFeeRate,
                                                            allowDustDonation: allowDustDonation)
        
        let transactionData = transaction.encode()
        try await outbox.save(transactionData: transactionData)
        
        let broadcastRequest = { [self] in
            let fulcrum = try await fulcrumPool.getFulcrum()
            let response = try await transaction.broadcast(using: fulcrum)
            guard !response.isEmpty else { throw Transaction.Error.cannotBroadcastTransaction }
            await outbox.remove(transactionHashData: HASH256.hash(transactionData))
        }
        
        if await fulcrumPool.currentStatus == .online {
            do { try await broadcastRequest() }
            catch { enqueueRequest(broadcastRequest) }
        } else {
            enqueueRequest(broadcastRequest)
        }
        
        let manuallyGeneratedTransactionHash = Transaction.Hash(naturalOrder: HASH256.hash(transactionData))
        
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
    
    public func monitorBalances() async throws -> AsyncThrowingStream<Satoshi, Swift.Error> {
        let addresses = await (addressBook.receivingEntries + addressBook.changeEntries).map { $0.address }
        guard !addresses.isEmpty else { throw Account.Monitor.Error.emptyAddresses }

        do {
            let fulcrum = try await fulcrumPool.getFulcrum()
            let stream = try await addressMonitor.start(for: addresses, using: fulcrum)
            
            return AsyncThrowingStream { continuation in
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        for try await _ in stream {
                            await self.refreshUTXOSet()
                            let balance = try await self.calculateBalance()
                            continuation.yield(balance)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                    
                    continuation.onTermination = { _ in
                        Task { [weak self] in await self?.addressMonitor.stop() }
                    }
                }
            }
        } catch {
            throw Account.Monitor.Error.monitoringFailed(error)
        }
    }
    
    public func stopBalanceMonitoring() async {
        await addressMonitor.stop()
    }
}
