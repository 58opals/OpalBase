// Network+FulcrumAddressReader.swift

import Foundation
import SwiftFulcrum

extension Network {
    public struct FulcrumAddressReader: AddressReadable {
        private let client: FulcrumClient
        private let timeouts: FulcrumRequestTimeout
        
        public init(client: FulcrumClient, timeouts: FulcrumRequestTimeout = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func fetchBalance(for address: String, tokenFilter: Network.TokenFilter) async throws -> AddressBalance {
            try await Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.address(.getBalance(address: address, tokenFilter: tokenFilter))),
                    responseType: Response.Result.Blockchain.Address.GetBalance.self,
                    options: .init(timeout: timeouts.addressBalance)
                )
                return AddressBalance(confirmed: result.confirmed, unconfirmed: result.unconfirmed)
            }
        }
        
        public func fetchUnspentOutputs(for address: String, tokenFilter: Network.TokenFilter) async throws -> [Transaction.Output.Unspent] {
            try await Network.performWithFailureTranslation {
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
                    method: .blockchain(.address(.listUnspent(address: address, tokenFilter: tokenFilter))),
                    responseType: Response.Result.Blockchain.Address.ListUnspent.self,
                    options: .init(timeout: timeouts.addressUnspent)
                )
                
                let unspentOutputs = try result.items.map { item in
                    guard let index = UInt32(exactly: item.transactionPosition) else {
                        throw Network.Failure(reason: .decoding, message: "Transaction position overflow")
                    }
                    let data = try Data(hexadecimalString: item.transactionHash)
                    let hash = Transaction.Hash(dataFromRPC: data)
                    let tokenData = try item.tokenData.map { try CashTokens.TokenData(swiftFulcrumTokenData: $0) }
                    return Transaction.Output.Unspent(
                        value: item.value,
                        lockingScript: lockingScriptData,
                        tokenData: tokenData,
                        previousTransactionHash: hash,
                        previousTransactionOutputIndex: index
                    )
                }
                
                return unspentOutputs.sorted { $0.compareOrder(before: $1) }
            }
        }
        
        public func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [TransactionHistoryEntry] {
            try await Network.performWithFailureTranslation {
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
                        fee: Network.resolveFee(transaction.fee)
                    )
                }
            }
        }
        
        public func fetchFirstUse(for address: String) async throws -> AddressFirstUse? {
            try await Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.address(.getFirstUse(address: address))),
                    responseType: Response.Result.Blockchain.Address.GetFirstUse.self,
                    options: .init(timeout: timeouts.addressFirstUse)
                )
                
                guard let blockHash = result.blockHash,
                      let blockHeight = result.height,
                      let transactionHash = result.transactionHash else {
                    return nil
                }
                
                return AddressFirstUse(blockHeight: blockHeight,
                                       blockHash: blockHash,
                                       transactionIdentifier: transactionHash)
            }
        }
        
        public func fetchMempoolTransactions(for address: String) async throws -> [TransactionHistoryEntry] {
            try await Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.address(.getMempool(address: address))),
                    responseType: Response.Result.Blockchain.Address.GetMempool.self,
                    options: .init(timeout: timeouts.addressMempool)
                )
                
                return result.transactions.map { transaction in
                    TransactionHistoryEntry(
                        transactionIdentifier: transaction.transactionHash,
                        blockHeight: transaction.height,
                        fee: Network.resolveFee(transaction.fee)
                    )
                }
            }
        }
        
        public func fetchScriptHash(for address: String) async throws -> String {
            try await Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.address(.getScriptHash(address: address))),
                    responseType: Response.Result.Blockchain.Address.GetScriptHash.self,
                    options: .init(timeout: timeouts.addressScriptHash)
                )
                return result.scriptHash
            }
        }
        
        public func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<AddressSubscriptionUpdate, any Error> {
            try await Network.performWithFailureTranslation {
                let (initial, updates, cancel) = try await client.subscribe(
                    method: .blockchain(.address(.subscribe(address: address))),
                    initialType: Response.Result.Blockchain.Address.Subscribe.self,
                    notificationType: Response.Result.Blockchain.Address.SubscribeNotification.self,
                    options: .init(timeout: timeouts.addressSubscription)
                )
                
                let subscribedAddress = address
                return Network.makeSubscriptionStream(
                    initial: initial,
                    updates: updates,
                    cancel: cancel,
                    makeInitialUpdates: { snapshot in
                        [
                            AddressSubscriptionUpdate(
                                kind: .initialSnapshot,
                                address: subscribedAddress,
                                status: snapshot.status
                            )
                        ]
                    },
                    makeUpdates: { notification in
                        guard subscribedAddress == notification.subscriptionIdentifier else { return .init() }
                        return [
                            AddressSubscriptionUpdate(
                                kind: .change,
                                address: subscribedAddress,
                                status: notification.status
                            )
                        ]
                    },
                    deduplicationKey: { update in
                        update.status
                    }
                )
            }
        }
    }
}
