import Foundation
import BigInt
import Combine
import SwiftFulcrum

extension Address {
    func fetchBalance(includeUnconfirmed: Bool = true,
                      using fulcrum: Fulcrum) async throws -> Satoshi {
        return try await Address.fetchBalance(for: self.string, includeUnconfirmed: includeUnconfirmed, using: fulcrum)
    }
    
    func fetchUnspentTransactionOutputs(fulcrum: Fulcrum) async throws -> [Transaction.Output.Unspent] {
        return try await Address.fetchUnspentTransactionOutputs(in: self, using: fulcrum)
    }
    
    func fetchTransactionHistory(fromHeight: UInt? = nil,
                                 toHeight: UInt? = nil,
                                 includeUnconfirmed: Bool = true,
                                 fulcrum: Fulcrum) async throws -> [Transaction.Simple] {
        return try await Address.fetchTransactionHistory(for: self, fromHeight: fromHeight, toHeight: toHeight, includeUnconfirmed: includeUnconfirmed, using: fulcrum)
    }
    
    func subscribe(fulcrum: inout Fulcrum) async throws -> (requestedID: UUID,
                                                            publisher: CurrentValueSubject<Response.JSONRPC.Result.Blockchain.Address.Subscribe?, Swift.Error>) {
        return try await Address.subscribeToActivities(of: self, using: &fulcrum)
    }
}

extension Address {
    static func fetchBalance(for address: String,
                             includeUnconfirmed: Bool = true,
                             using fulcrum: Fulcrum) async throws -> Satoshi {
        let (id, publisher) = try await fulcrum.submit(
            method: .blockchain(.address(.getBalance(address: address, tokenFilter: nil))),
            responseType: Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.Address.GetBalance>.self
        )
        
        let balance = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt64, Swift.Error>) in
            let subscription = publisher
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            return//print("\(id): fetching balance of \(address) request completed.")
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    },
                    receiveValue: { response in
                        let totalBalance = UInt64(BigInt(response.confirmed) + BigInt(includeUnconfirmed ? response.unconfirmed : 0))
                        continuation.resume(returning: totalBalance)
                    }
                )
            
            fulcrum.subscriptionHub.add(subscription, for: id)
        }
        
        return try Satoshi(balance)
    }
    
    static func fetchUnspentTransactionOutputs(in address: Address,
                                               using fulcrum: Fulcrum) async throws -> [Transaction.Output.Unspent] {
        let (id, publisher) = try await fulcrum.submit(
            method: .blockchain(.address(
                .listUnspent(address: address.string,
                             tokenFilter: nil)
            )),
            responseType: Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.Address.ListUnspent>.self
        )
        
        let utxos = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Response.JSONRPC.Result.Blockchain.Address.ListUnspent, Swift.Error>) in
            let subscription = publisher
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            return//print("\(id): fetching utxos in \(address) request completed.")
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    },
                    receiveValue: { response in
                        continuation.resume(returning: response)
                    }
                )
            
            fulcrum.subscriptionHub.add(subscription, for: id)
        }
        
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
    
    static func fetchTransactionHistory(for address: Address,
                                        fromHeight: UInt? = nil,
                                        toHeight: UInt? = nil,
                                        includeUnconfirmed: Bool = true,
                                        using fulcrum: Fulcrum) async throws -> [Transaction.Simple] {
        let (id, publisher) = try await fulcrum.submit(
            method: .blockchain(.address(
                .getHistory(address: address.string,
                            fromHeight: fromHeight,
                            toHeight: toHeight,
                            includeUnconfirmed: includeUnconfirmed)
            )),
            responseType: Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.Address.GetHistory>.self
        )
        
        let history = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Response.JSONRPC.Result.Blockchain.Address.GetHistoryItem], Swift.Error>) in
            let subscription = publisher
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            return//print("\(id): getting history of \(address) request completed.")
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    },
                    receiveValue: { response in
                        continuation.resume(returning: response)
                    }
                )
            
            fulcrum.subscriptionHub.add(subscription, for: id)
        }
        
        let transactions = try history.map { historyItem in
            return Transaction.Simple(transactionHash: .init(dataFromRPC: try .init(hexString: historyItem.tx_hash)),
                                      height: UInt32(historyItem.height),
                                      fee: { if let fee = historyItem.fee { return UInt64?(.init(fee)) } else { return nil } }())
        }
        
        return transactions
    }
    
    static func subscribeToActivities(of address: Address,
                                      using fulcrum: inout Fulcrum) async throws -> (requestedID: UUID,
                                                                                     publisher: CurrentValueSubject<Response.JSONRPC.Result.Blockchain.Address.Subscribe?, Swift.Error>) {
        let (id, publisher) = try await fulcrum.submit(
            method: .blockchain(.address(
                .subscribe(address: address.string)
            )),
            notificationType: Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.Address.Subscribe>.self
        )
        
        return (id, publisher)
    }
}
