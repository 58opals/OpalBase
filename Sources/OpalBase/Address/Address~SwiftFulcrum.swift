// Address~SwiftFulcrum.swift

import Foundation
import BigInt
import SwiftFulcrum

extension Address {
    func fetchBalance(includeUnconfirmed: Bool = true, using fulcrum: Fulcrum) async throws -> Satoshi {
        return try await Address.fetchBalance(for: self, includeUnconfirmed: includeUnconfirmed, using: fulcrum)
    }
    
    func fetchUnspentTransactionOutputs(fulcrum: Fulcrum) async throws -> [Transaction.Output.Unspent] {
        return try await Address.fetchUnspentTransactionOutputs(in: self, using: fulcrum)
    }
    
    func fetchSimpleTransactionHistory(fromHeight: UInt? = nil,
                                       toHeight: UInt? = nil,
                                       includeUnconfirmed: Bool = true,
                                       fulcrum: Fulcrum) async throws -> [Transaction.Simple] {
        return try await Address.fetchSimpleTransactionHistory(for: self,
                                                               fromHeight: fromHeight,
                                                               toHeight: toHeight,
                                                               includeUnconfirmed: includeUnconfirmed,
                                                               using: fulcrum)
    }
    
    func fetchSimpleTransactionHistoryPage(fromHeight: UInt? = nil,
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
    
    func fetchFullTransactionHistory(fromHeight: UInt? = nil,
                                     toHeight: UInt? = nil,
                                     includeUnconfirmed: Bool = true,
                                     fulcrum: Fulcrum) async throws -> [Transaction.Detailed] {
        return try await Address.fetchFullTransactionHistory(for: self,
                                                             fromHeight: fromHeight,
                                                             toHeight: toHeight,
                                                             includeUnconfirmed: includeUnconfirmed,
                                                             using: fulcrum)
    }
    
    func fetchFullTransactionHistoryPage(fromHeight: UInt? = nil,
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
    
    func subscribe(fulcrum: Fulcrum) async throws -> (requestedID: UUID,
                                                      initialStatus: String,
                                                      followingStatus: AsyncThrowingStream<Response.Result.Blockchain.Address.SubscribeNotification, Swift.Error>,
                                                      cancel: @Sendable () async -> Void) {
        let (id, result, notifications, cancel) = try await Address.subscribeToActivities(of: self, using: fulcrum)
        
        let requestedID = id
        let initialStatus = result.status ?? ""
        let followingStatus = notifications
        let cancelSubscription = cancel
        
        return (requestedID, initialStatus, followingStatus, cancelSubscription)
    }
}

extension Address {
    static func fetchBalance(for address: Address, includeUnconfirmed: Bool = true, using fulcrum: Fulcrum) async throws -> Satoshi {
        let response = try await fulcrum.submit(method: .blockchain(.address(.getBalance(address: address.string, tokenFilter: nil))),
                                                responseType: Response.Result.Blockchain.Address.GetBalance.self)
        guard case .single(let id, let result) = response else { throw Fulcrum.Error.coding(.decode(nil)) }
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        let delta = includeUnconfirmed ? result.unconfirmed : 0
        let balance: UInt64
        if delta >= 0 {
            balance = result.confirmed &+ UInt64(delta)
        } else {
            let decrease = UInt64(-delta)
            balance = result.confirmed > decrease ? (result.confirmed - decrease) : 0
        }
        
        return try Satoshi(balance)
    }
    
    static func fetchUnspentTransactionOutputs(in address: Address, using fulcrum: Fulcrum) async throws -> [Transaction.Output.Unspent] {
        do {
            let scriptHash = SHA256.hash(address.lockingScript.data).reversedData
            let response = try await fulcrum.submit(
                method: .blockchain(.scripthash(.listUnspent(scripthash: scriptHash.hexadecimalString, tokenFilter: nil))),
                responseType: Response.Result.Blockchain.ScriptHash.ListUnspent.self
            )
            guard case .single(let id, let result) = response else { throw Fulcrum.Error.coding(.decode(nil)) }
            assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
            
            return try result.items.map { item in
                let transactionHash = Transaction.Hash(reverseOrder: try Data(hexString: item.transactionHash))
                let outputIndex = UInt32(item.transactionPosition)
                return Transaction.Output.Unspent(value: item.value,
                                                  lockingScript: address.lockingScript.data,
                                                  previousTransactionHash: transactionHash,
                                                  previousTransactionOutputIndex: outputIndex)
            }
        } catch {
            let response = try await fulcrum.submit(
                method: .blockchain(.address(.listUnspent(address: address.string, tokenFilter: nil))),
                responseType: Response.Result.Blockchain.Address.ListUnspent.self
            )
            guard case .single(let id, let result) = response else { throw Fulcrum.Error.coding(.decode(nil)) }
            assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
            
            var unspentTransactionOutputs: [Transaction.Output.Unspent] = .init()
            var needs: [(transactionHash: Transaction.Hash, outputIndex: UInt32, value: UInt64)] = .init()
            
            for utxo in result.items {
                let transactionHash = try Data(hexString: utxo.transactionHash)
                let outputIndex = UInt32(utxo.transactionPosition)
                let value = utxo.value
                
                if address.lockingScript.isDerivableFromAddress {
                    unspentTransactionOutputs.append(.init(value: value,
                                                           lockingScript: address.lockingScript.data,
                                                           previousTransactionHash: .init(dataFromRPC: transactionHash),
                                                           previousTransactionOutputIndex: outputIndex))
                } else {
                    needs.append(
                        (transactionHash: .init(dataFromRPC: transactionHash),
                         outputIndex: outputIndex,
                         value: value)
                    )
                }
            }
            
            if !needs.isEmpty {
                let unique = Array(Set(needs.map { $0.transactionHash }))
                let gateway = Network.Gateway(client: Adapter.SwiftFulcrum.GatewayClient(fulcrum: fulcrum))
                await gateway.updateHealth(status: .online, lastHeaderAt: Date())
                let fetched = try await Transaction.fetchFullTransactionsBatched(for: unique, using: gateway)
                for need in needs {
                    if let detailed = fetched[need.transactionHash.originalData],
                       Int(need.outputIndex) < detailed.transaction.outputs.count {
                        let script = detailed.transaction.outputs[Int(need.outputIndex)].lockingScript
                        unspentTransactionOutputs.append(.init(value: need.value,
                                                               lockingScript: script,
                                                               previousTransactionHash: need.transactionHash,
                                                               previousTransactionOutputIndex: need.outputIndex))
                    }
                }
            }
            
            return unspentTransactionOutputs
        }
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
                                                                                                    result: Response.Result.Blockchain.Address.Subscribe,
                                                                                                    notifications: AsyncThrowingStream<Response.Result.Blockchain.Address.SubscribeNotification, Swift.Error>,
                                                                                                    cancel: @Sendable () async -> Void) {
        let response: Fulcrum.RPCResponse<
            Response.Result.Blockchain.Address.Subscribe,
            Response.Result.Blockchain.Address.SubscribeNotification
        > = try await fulcrum.submit(
            method: .blockchain(.address(.subscribe(address: address.string)))
        )
        guard case .stream(let id, let initialResponse, let updates, let cancel) = response else { throw Fulcrum.Error.coding(.decode(nil)) }
        
        return (id, initialResponse, updates, cancel)
    }
}
