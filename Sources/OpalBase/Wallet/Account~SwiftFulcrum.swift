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
    
    public func startAddressMonitoring() async throws {
        let addresses = await (addressBook.receivingEntries + addressBook.changeEntries).map { $0.address }
        guard !addresses.isEmpty else { return }
        
        do {
            let fulcrum = try await fulcrumPool.getFulcrum()
            let stream = try await addressMonitor.start(for: addresses, using: fulcrum)
            
            Task { [weak self] in
                guard let self else { return }
                let continuation = await self.balanceStreamContinuation
                do {
                    for try await _ in stream {
                        await self.refreshUTXOSet()
                        let balance = try await self.calculateBalance()
                        continuation?.yield(balance.uint64)
                    }
                } catch {
                    continuation?.finish(throwing: error)
                }
            }
        } catch {
            throw Account.Monitor.Error.monitoringFailed(error)
        }
    }
    
    public func stopAddressMonitoring() async {
        await addressMonitor.stop()
        balanceStreamContinuation?.finish()
    }
}
