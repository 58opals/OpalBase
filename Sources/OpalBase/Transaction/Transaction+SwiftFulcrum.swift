import Foundation
import Combine
import SwiftFulcrum

extension Transaction {
    func broadcast(using fulcrum: Fulcrum) async throws -> Data {
        let (id, publisher) = try await fulcrum.submit(
            method: .blockchain(.transaction(
                .broadcast(rawTransaction: self.encode().hexadecimalString)
            )),
            responseType: Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.Transaction.Broadcast>.self
        )
        
        let broadcastedTransaction = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Swift.Error>) in
            let subscription = publisher
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            return//print("\(id): broadcasting a raw transaction request completed.")
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    },
                    receiveValue: { response in
                        continuation.resume(returning: response)
                    })
            
            fulcrum.subscriptionHub.add(subscription, for: id)
        }
        
        return broadcastedTransaction
    }
}

extension Transaction {
    static func estimateFee(numberOfBlocks: Int,
                            using fulcrum: Fulcrum) async throws -> Satoshi {
        let (id, publisher) = try await fulcrum.submit(
            method: .blockchain(
                .estimateFee(numberOfBlocks: numberOfBlocks)
            ),
            responseType: Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.EstimateFee>.self
        )
        
        let fee = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Satoshi, Swift.Error>) in
            let subscription = publisher
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            return//print("\(id): getting estimate fee for \(numberOfBlocks) block(s) request completed.")
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    },
                    receiveValue: { response in
                        do {
                            let satoshi = try Satoshi(bch: response)
                            continuation.resume(returning: satoshi)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    })
            
            fulcrum.subscriptionHub.add(subscription, for: id)
        }
        
        return fee
    }
    
    static func relayFee(using fulcrum: Fulcrum) async throws -> Satoshi {
        let (id, publisher) = try await fulcrum.submit(
            method: .blockchain(
                .relayFee
            ),
            responseType: Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.RelayFee>.self
        )
        
        let fee = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Satoshi, Swift.Error>) in
            let subscription = publisher
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            return//print("\(id): getting relay fee request completed.")
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    },
                    receiveValue: { response in
                        do {
                            let satoshi = try Satoshi(bch: response)
                            continuation.resume(returning: satoshi)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    })
            
            fulcrum.subscriptionHub.add(subscription, for: id)
        }
        
        return fee
    }
}

extension Transaction {
    static func fetchRawData(for transactionHash: Data,
                             using fulcrum: Fulcrum) async throws -> Data {
        let (id, publisher) = try await fulcrum.submit(
            method: .blockchain(.transaction(
                .get(transactionHash: transactionHash.hexadecimalString,
                     verbose: true)
            )),
            responseType: Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.Transaction.Get>.self
        )
        
        let transaction = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Swift.Error>) in
            let subscription = publisher
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            return//print("\(id): fetching a raw transaction data of \(transactionHash.hexadecimalString) request completed.")
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    },
                    receiveValue: { response in
                        let data = Data(hex: response.hex)
                        continuation.resume(returning: data)
                    })
            
            fulcrum.subscriptionHub.add(subscription, for: id)
        }
        
        return transaction
    }
    
    static func fetchTransaction(for transactionHash: Data,
                                 using fulcrum: Fulcrum) async throws -> Transaction {
        let (id, publisher) = try await fulcrum.submit(
            method: .blockchain(.transaction(
                .get(transactionHash: transactionHash.hexadecimalString,
                     verbose: true))),
            responseType: Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.Transaction.Get>.self
        )
        
        let transaction = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Transaction, Swift.Error>) in
            let subscription = publisher
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            return//print("\(id): fetching transaction information of \(transactionHash.hexadecimalString) request completed.")
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    },
                    receiveValue: { response in
                        do {
                            let transaction = Transaction(version: UInt32(response.version),
                                                          inputs: response.vin.map { Input(previousTransactionHash: .init(dataFromRPC: Data(hex: $0.txid)),
                                                                                           previousTransactionOutputIndex: UInt32($0.vout),
                                                                                           unlockingScript: Data(hex: $0.scriptSig.hex),
                                                                                           sequence: UInt32($0.sequence)) },
                                                          outputs: try response.vout.map { Output(value: try Satoshi(bch: $0.value).uint64,
                                                                                                  lockingScript: Data(hex: $0.scriptPubKey.hex)) },
                                                          lockTime: UInt32(response.locktime))
                            continuation.resume(returning: transaction)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    })
            fulcrum.subscriptionHub.add(subscription, for: id)
        }
        
        return transaction
    }
    
    static func fetchFullTransaction(for transactionHash: Data,
                                     using fulcrum: Fulcrum) async throws -> Transaction.Detailed {
        let (id, publisher) = try await fulcrum.submit(
            method: .blockchain(.transaction(
                .get(transactionHash: transactionHash.hexadecimalString,
                     verbose: true)
            )),
            responseType: Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.Transaction.Get>.self
        )
        
        let fullTransaction = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Transaction.Detailed, Swift.Error>) in
            let subscription = publisher
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            return//print("\(id): fetching full transaction detilas of \(transactionHash.hexadecimalString) request completed.")
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    },
                    receiveValue: { response in
                        let isUnconfirmed = (response.blockhash == nil) && (response.blocktime == nil) && (response.confirmations == nil) && (response.time == nil)
                        
                        do {
                            let transaction = Transaction(version: UInt32(response.version),
                                                          inputs: response.vin.map { Input(previousTransactionHash: .init(dataFromRPC: Data(hex: $0.txid)),
                                                                                           previousTransactionOutputIndex: UInt32($0.vout),
                                                                                           unlockingScript: Data(hex: $0.scriptSig.hex),
                                                                                           sequence: UInt32($0.sequence)) },
                                                          outputs: try response.vout.map { Output(value: try Satoshi(bch: $0.value).uint64,
                                                                                                  lockingScript: Data(hex: $0.scriptPubKey.hex)) },
                                                          lockTime: UInt32(response.locktime))
                            let detailedTransaction = Transaction.Detailed(transaction: transaction,
                                                                           blockHash: isUnconfirmed ? nil : Data(hex: response.blockhash!),
                                                                           blockTime: isUnconfirmed ? nil : UInt32(response.blocktime!),
                                                                           confirmations: isUnconfirmed ? nil : UInt32(response.confirmations!),
                                                                           hash: Data(hex: response.hash),
                                                                           hex: Data(hex: response.hex),
                                                                           size: UInt32(response.size),
                                                                           time: isUnconfirmed ? nil : UInt32(response.time!))
                            continuation.resume(returning: detailedTransaction)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    })
            fulcrum.subscriptionHub.add(subscription, for: id)
        }
        
        return fullTransaction
    }
}
