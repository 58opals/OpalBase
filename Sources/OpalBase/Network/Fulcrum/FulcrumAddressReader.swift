// Network+FulcrumAddressReader~Fulcrum.swift

import Foundation
import SwiftFulcrum

extension Network {
    public struct FulcrumAddressReader: AddressReadable {
        private let client: FulcrumClient
        private let timeouts: FulcrumRequestTimeouts
        
        public init(client: FulcrumClient, timeouts: FulcrumRequestTimeouts = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func fetchBalance(for address: String) async throws -> AddressBalance {
            do {
                let result = try await client.request(
                    method: .blockchain(.address(.getBalance(address: address, tokenFilter: nil))),
                    responseType: Response.Result.Blockchain.Address.GetBalance.self,
                    options: .init(timeout: timeouts.addressBalance)
                )
                return AddressBalance(confirmed: result.confirmed, unconfirmed: result.unconfirmed)
            } catch {
                throw FulcrumErrorTranslator.translate(error)
            }
        }
        
        public func fetchUnspentOutputs(for address: String) async throws -> [Transaction.Output.Unspent] {
            do {
                let lockingScriptData: Data
                do {
                    lockingScriptData = try Address(address).lockingScript.data
                } catch {
                    throw Network.Failure(
                        reason: .protocolViolation,
                        message: "Invalid address provided: \(address)"
                    )
                }
                
                let result = try await client.request(
                    method: .blockchain(.address(.listUnspent(address: address, tokenFilter: nil))),
                    responseType: Response.Result.Blockchain.Address.ListUnspent.self,
                    options: .init(timeout: timeouts.addressUnspent)
                )
                
                return try result.items.map { item in
                    guard let index = UInt32(exactly: item.transactionPosition) else {
                        throw Network.Failure(reason: .decoding, message: "Transaction position overflow")
                    }
                    let data = try Data(hexadecimalString: item.transactionHash)
                    let hash = Transaction.Hash(dataFromRPC: data)
                    return Transaction.Output.Unspent(
                        value: item.value,
                        lockingScript: lockingScriptData,
                        previousTransactionHash: hash,
                        previousTransactionOutputIndex: index
                    )
                }
            } catch let failure as Network.Failure {
                throw failure
            } catch let error as Data.Error {
                throw Network.Failure(reason: .decoding, message: error.localizedDescription)
            } catch {
                throw FulcrumErrorTranslator.translate(error)
            }
        }
        
        public func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [TransactionHistoryEntry] {
            do {
                let result = try await client.request(
                    method: .blockchain(
                        .address(
                            .getHistory(
                                address: address,
                                fromHeight: nil,
                                toHeight: nil,
                                includeUnconfirmed: includeUnconfirmed
                            )
                        )
                    ),
                    responseType: Response.Result.Blockchain.Address.GetHistory.self,
                    options: .init(timeout: timeouts.addressHistory)
                )
                
                return result.transactions.map { transaction in
                    TransactionHistoryEntry(
                        transactionIdentifier: transaction.transactionHash,
                        blockHeight: transaction.height,
                        fee: transaction.fee
                    )
                }
            } catch {
                throw FulcrumErrorTranslator.translate(error)
            }
        }
        
        public func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<AddressSubscriptionUpdate, any Error> {
            do {
                let (initial, updates, cancel) = try await client.subscribe(
                    method: .blockchain(.address(.subscribe(address: address))),
                    initialType: Response.Result.Blockchain.Address.Subscribe.self,
                    notificationType: Response.Result.Blockchain.Address.SubscribeNotification.self,
                    options: .init(timeout: timeouts.addressSubscription)
                )
                
                return AsyncThrowingStream { continuation in
                    var lastStatus = initial.status
                    let initialUpdate = AddressSubscriptionUpdate(kind: .initialSnapshot, address: address, status: initial.status)
                    continuation.yield(initialUpdate)
                    
                    let task = Task {
                        do {
                            for try await notification in updates {
                                let update = AddressSubscriptionUpdate(kind: .change, address: notification.subscriptionIdentifier, status: notification.status)
                                guard update.status != lastStatus else { continue }
                                lastStatus = update.status
                                continuation.yield(update)
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: FulcrumErrorTranslator.translate(error))
                        }
                    }
                    
                    continuation.onTermination = { _ in
                        task.cancel()
                        Task { await cancel() }
                    }
                }
            } catch {
                throw FulcrumErrorTranslator.translate(error)
            }
        }
    }
}
