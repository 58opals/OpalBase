// Address~SwiftFulcrum.swift

import Foundation
import BigInt
import SwiftFulcrum

extension Address {
    public func fetchBalance(includeUnconfirmed: Bool = true, using fulcrum: Fulcrum) async throws -> Satoshi {
        return try await Address.fetchBalance(for: self, includeUnconfirmed: includeUnconfirmed, using: fulcrum)
    }
    
    public func fetchUnspentTransactionOutputs(fulcrum: Fulcrum) async throws -> [Transaction.Output.Unspent] {
        return try await Address.fetchUnspentTransactionOutputs(in: self, using: fulcrum)
    }
    
    public func fetchSimpleTransactionHistory(fromHeight: UInt? = nil,
                                              toHeight: UInt? = nil,
                                              includeUnconfirmed: Bool = true,
                                              fulcrum: Fulcrum) async throws -> [Transaction.Simple] {
        return try await Address.fetchSimpleTransactionHistory(for: self,
                                                               fromHeight: fromHeight,
                                                               toHeight: toHeight,
                                                               includeUnconfirmed: includeUnconfirmed,
                                                               using: fulcrum)
    }
    
    public func fetchSimpleTransactionHistoryPage(fromHeight: UInt? = nil,
                                                  window: UInt,
                                                  includeUnconfirmed: Bool = true,
                                                  fulcrum: Fulcrum) async throws -> Address.Book.Page<Transaction.Simple> {
        let startHeight = fromHeight ?? 0
        let endHeight = (window == 0) ? nil : ((startHeight &+ window) &- 1)
        let transactions = try await self.fetchSimpleTransactionHistory(fromHeight: startHeight,
                                                                        toHeight: endHeight,
                                                                        includeUnconfirmed: includeUnconfirmed,
                                                                        fulcrum: fulcrum)
        let nextHeight = endHeight.map { $0 &+ 1 }
        
        return .init(transactions: transactions, nextFromHeight: nextHeight)
    }
    
    public func fetchFullTransactionHistory(fromHeight: UInt? = nil,
                                            toHeight: UInt? = nil,
                                            includeUnconfirmed: Bool = true,
                                            fulcrum: Fulcrum) async throws -> [Transaction.Detailed] {
        return try await Address.fetchFullTransactionHistory(for: self,
                                                             fromHeight: fromHeight,
                                                             toHeight: toHeight,
                                                             includeUnconfirmed: includeUnconfirmed,
                                                             using: fulcrum)
    }
    
    public func fetchFullTransactionHistoryPage(fromHeight: UInt? = nil,
                                                window: UInt,
                                                includeUnconfirmed: Bool = true,
                                                fulcrum: Fulcrum) async throws -> Address.Book.Page<Transaction.Detailed> {
        let startHeight = fromHeight ?? 0
        let endHeight = (window == 0) ? nil : ((startHeight &+ window) &- 1)
        let transactions = try await self.fetchFullTransactionHistory(fromHeight: startHeight,
                                                                        toHeight: endHeight,
                                                                        includeUnconfirmed: includeUnconfirmed,
                                                                        fulcrum: fulcrum)
        let nextHeight = endHeight.map { $0 &+ 1 }
        
        return .init(transactions: transactions, nextFromHeight: nextHeight)
    }
    
    public func subscribe(fulcrum: Fulcrum) async throws -> (requestedID: UUID,
                                                             subscriptionID: String,
                                                             initialStatus: String,
                                                             followingStatus: AsyncThrowingStream<Response.Result.Blockchain.Address.SubscribeNotification, Swift.Error>,
                                                             cancel: () async -> Void) {
        let (id, result, notifications, cancel) = try await Address.subscribeToActivities(of: self, using: fulcrum)
        
        let requestedID = id
        let subscriptionID = result.subscriptionIdentifier
        let initialStatus = result.status ?? ""
        let followingStatus = notifications
        let cancelSubscription = cancel
        
        return (requestedID, subscriptionID, initialStatus, followingStatus, cancelSubscription)
    }
}

extension Address {
    static func fetchBalance(for address: Address, includeUnconfirmed: Bool = true, using fulcrum: Fulcrum) async throws -> Satoshi {
        let response = try await fulcrum.submit(method: .blockchain(.address(.getBalance(address: address.string, tokenFilter: nil))),
                                                responseType: Response.Result.Blockchain.Address.GetBalance.self)
        guard case .single(let id, let result) = response else { throw Fulcrum.Error.coding(.decode(nil)) }
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        let balance = result.confirmed + UInt64((includeUnconfirmed ? result.unconfirmed : 0))
        
        return try Satoshi(balance)
    }
    
    static func fetchUnspentTransactionOutputs(in address: Address, using fulcrum: Fulcrum) async throws -> [Transaction.Output.Unspent] {
        let response = try await fulcrum.submit(method: .blockchain(.address(.listUnspent(address: address.string, tokenFilter: nil))),
                                                responseType: Response.Result.Blockchain.Address.ListUnspent.self)
        guard case .single(let id, let result) = response else { throw Fulcrum.Error.coding(.decode(nil)) }
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        let utxos = result.items
        var unspentTransactionOutputs: [Transaction.Output.Unspent] = .init()
        for utxo in utxos {
            let transactionHash = Transaction.Hash(reverseOrder: try Data(hexString: utxo.transactionHash))
            let outputIndex = UInt32(utxo.transactionPosition)
            let amount = utxo.value
            let fullTransaction = try await Transaction.fetchFullTransaction(for: transactionHash.externallyUsedFormat, using: fulcrum)
            let lockingScript = fullTransaction.transaction.outputs[Int(outputIndex)].lockingScript
            unspentTransactionOutputs.append(.init(value: amount,
                                                   lockingScript: lockingScript,
                                                   previousTransactionHash: transactionHash,
                                                   previousTransactionOutputIndex: outputIndex))
        }
        
        return unspentTransactionOutputs
    }
    
    static func fetchSimpleTransactionHistory(for address: Address,
                                              fromHeight: UInt? = nil,
                                              toHeight: UInt? = nil,
                                              includeUnconfirmed: Bool = true,
                                              using fulcrum: Fulcrum) async throws -> [Transaction.Simple] {
        let response = try await fulcrum.submit(method: .blockchain(.address(.getHistory(address: address.string,
                                                                                         fromHeight: fromHeight,
                                                                                         toHeight: toHeight,
                                                                                         includeUnconfirmed: includeUnconfirmed))),
                                                responseType: Response.Result.Blockchain.Address.GetHistory.self)
        guard case .single(let id, let result) = response else { throw Fulcrum.Error.coding(.decode(nil)) }
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        let history = result.transactions
        let transactions = try history.map { historyItem in
            return Transaction.Simple(transactionHash: .init(dataFromRPC: try .init(hexString: historyItem.transactionHash)),
                                      height: (historyItem.height <= 0) ? nil : UInt32(historyItem.height),
                                      fee: { if let fee = historyItem.fee { return UInt64?(.init(fee)) } else { return nil } }() )
        }
        
        return transactions
    }
    
    static func fetchFullTransactionHistory(for address: Address, fromHeight: UInt? = nil, toHeight: UInt? = nil, includeUnconfirmed: Bool = true, using fulcrum: Fulcrum) async throws -> [Transaction.Detailed] {
        let simpleTransactions = try await self.fetchSimpleTransactionHistory(for: address,
                                                                              fromHeight: fromHeight,
                                                                              toHeight: toHeight,
                                                                              includeUnconfirmed: includeUnconfirmed,
                                                                              using: fulcrum)
        
        return try await withThrowingTaskGroup(of: Transaction.Detailed.self) { group in
            for simpleTransaction in simpleTransactions {
                group.addTask {
                    let response = try await fulcrum.submit(method: .blockchain(.transaction(.get(transactionHash: simpleTransaction.transactionHash.externallyUsedFormat.hexadecimalString, verbose: true))),
                                                            responseType: Response.Result.Blockchain.Transaction.Get.self)
                    guard case .single(let id, let result) = response else { throw Fulcrum.Error.coding(.decode(nil)) }
                    
                    assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
                    
                    let detailedTransaction = try Transaction.Detailed(from: result)
                    
                    return detailedTransaction
                }
            }
            
            var detailedTransactions = [Transaction.Detailed]()
            for try await transaction in group {
                detailedTransactions.append(transaction)
            }
            
            return detailedTransactions
        }
    }
    
    static func subscribeToActivities(of address: Address, using fulcrum: Fulcrum) async throws -> (requestedID: UUID,
                                                                                                    result: Response.Result.Blockchain.Address.SubscribeNotification,
                                                                                                    notifications: AsyncThrowingStream<Response.Result.Blockchain.Address.SubscribeNotification, Swift.Error>,
                                                                                                    cancel: () async -> Void) {
        let response = try await fulcrum.submit(method: .blockchain(.address(.subscribe(address: address.string))),
                                                notificationType: Response.Result.Blockchain.Address.SubscribeNotification.self)
        guard case .stream(let id, let initialResponse, let updates, let cancel) = response else { throw Fulcrum.Error.coding(.decode(nil)) }
        
        return (id, initialResponse, updates, cancel)
    }
}
