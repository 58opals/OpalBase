import Foundation
import BigInt
import SwiftFulcrum

extension Address {
    public func fetchBalance(includeUnconfirmed: Bool = true,
                             using fulcrum: Fulcrum) async throws -> Satoshi {
        return try await Address.fetchBalance(for: self.string, includeUnconfirmed: includeUnconfirmed, using: fulcrum)
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
    
    public func subscribe(fulcrum: Fulcrum) async throws -> (requestedID: UUID,
                                                             initialStatus: String,
                                                             followingStatus: AsyncThrowingMapSequence<AsyncStream<Response.JSONRPC.Result.Blockchain.Address.Subscribe?>, String>) {
        let (id, result, notifications) = try await Address.subscribeToActivities(of: self, using: fulcrum)
        
        var initialStatus: String
        var followingStatus: AsyncThrowingMapSequence<AsyncStream<Response.JSONRPC.Result.Blockchain.Address.Subscribe?>, String>
        
        switch result {
        case .status(let status):
            initialStatus = status
            followingStatus = notifications.map { notification in
                switch notification {
                case .status(let status):
                    return status
                case .addressAndStatus(let addressAndStatus):
                    guard let address = addressAndStatus[0] else { throw Fulcrum.Error.resultNotFound(description: "Address is missing.") }
                    if let status = addressAndStatus[1] {
                        return status
                    } else {
                        throw Fulcrum.Error.resultNotFound(description: "Status of the address \(address) not found.")
                    }
                case .none:
                    throw Fulcrum.Error.resultNotFound(description: "Result of the address not found.")
                }
            }
        case .addressAndStatus(let addressAndStatus):
            guard let address = addressAndStatus[0] else { throw Fulcrum.Error.resultNotFound(description: "Address is missing.") }
            guard address == self.string else { throw Fulcrum.Error.custom(description: "Address \(address) does not match \(self.string).") }
            if let status = addressAndStatus[1] {
                initialStatus = status
            } else {
                throw Fulcrum.Error.resultNotFound(description: "Status of the address \(address) not found.")
            }
            fatalError()
        case .none:
            throw Fulcrum.Error.resultNotFound(description: "Result of the address \(self.string) not found.")
        }
        
        return (id, initialStatus, followingStatus)
    }
}

extension Address {
    static func fetchBalance(for address: String,
                             includeUnconfirmed: Bool = true,
                             using fulcrum: Fulcrum) async throws -> Satoshi {
        let (id, result) = try await fulcrum.submit(
            method:
                Method
                .blockchain(.address(.getBalance(address: address, tokenFilter: nil))),
            responseType:
                Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.Address.GetBalance>.self
        )
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        var balance = UInt64(0)
        if includeUnconfirmed {
            let confirmedBalance = Int64(result.confirmed)
            let unconfirmedBalance = result.unconfirmed
            let calculatedBalance = confirmedBalance + unconfirmedBalance
            
            balance = UInt64(calculatedBalance)
        }
        
        return try Satoshi(balance)
    }
    
    static func fetchUnspentTransactionOutputs(in address: Address,
                                               using fulcrum: Fulcrum) async throws -> [Transaction.Output.Unspent] {
        let (id, result) = try await fulcrum.submit(
            method:
                Method
                .blockchain(.address(.listUnspent(address: address.string, tokenFilter: nil))),
            responseType:
                Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.Address.ListUnspent>.self
        )
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        let utxos = result
        
        var unspentTransactionOutputs: [Transaction.Output.Unspent] = .init()
        
        for utxo in utxos {
            let transactionHashFromRPC = try Data(hexString: utxo.tx_hash)
            let transactionHash = Transaction.Hash(reverseOrder: transactionHashFromRPC)
            let outputIndex = UInt32(utxo.tx_pos)
            let amount = utxo.value
            
            let fullTransaction = try await Transaction.fetchFullTransaction(for: transactionHash.externallyUsedFormat,
                                                                             using: fulcrum)
            
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
        
        let (id, result) = try await fulcrum.submit(
            method:
                Method
                .blockchain(.address(.getHistory(address: address.string, fromHeight: fromHeight, toHeight: toHeight, includeUnconfirmed: includeUnconfirmed))),
            responseType:
                Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.Address.GetHistory>.self
        )
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        let history = result
        let transactions = try history.map { historyItem in
            return Transaction.Simple(transactionHash: .init(dataFromRPC: try .init(hexString: historyItem.tx_hash)),
                                      height: (historyItem.height <= 0) ? nil : UInt32(historyItem.height),
                                      fee: { if let fee = historyItem.fee { return UInt64?(.init(fee)) } else { return nil } }())
        }
        
        return transactions
    }
    
    static func fetchFullTransactionHistory(for address: Address,
                                            fromHeight: UInt? = nil,
                                            toHeight: UInt? = nil,
                                            includeUnconfirmed: Bool = true,
                                            using fulcrum: Fulcrum) async throws -> [Transaction.Detailed] {
        
        let simpleTransactions = try await self.fetchSimpleTransactionHistory(for: address,
                                                                              fromHeight: fromHeight,
                                                                              toHeight: toHeight,
                                                                              includeUnconfirmed: includeUnconfirmed,
                                                                              using: fulcrum)
        
        return try await withThrowingTaskGroup(of: Transaction.Detailed.self) { group in
            for simpleTransaction in simpleTransactions {
                group.addTask {
                    let (_, result) = try await fulcrum.submit(
                        method:
                            Method
                            .blockchain(.transaction(.get(transactionHash: simpleTransaction.transactionHash.bigEndian.hexadecimalString, verbose: true))),
                        responseType:
                            Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.Transaction.Get>.self
                    )
                    
                    return try Transaction.Detailed(from: result)
                }
            }
            
            var detailedTransactions = [Transaction.Detailed]()
            for try await transaction in group {
                detailedTransactions.append(transaction)
            }
            
            return detailedTransactions
        }
    }
    
    static func subscribeToActivities(of address: Address,
                                      using fulcrum: Fulcrum) async throws -> (requestedID: UUID,
                                                                               result: Response.JSONRPC.Result.Blockchain.Address.Subscribe?,
                                                                               notifications: AsyncStream<Response.JSONRPC.Result.Blockchain.Address.Subscribe?>) {
        let (id, result, notifications) = try await fulcrum.submit(
            method:
                Method
                .blockchain(.address(.subscribe(address: address.string))),
            notificationType:
                Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.Address.Subscribe>.self
        )
        
        return (id, result, notifications)
    }
}
