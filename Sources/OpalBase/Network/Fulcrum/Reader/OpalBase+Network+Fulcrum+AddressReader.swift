// OpalBase+Network+Fulcrum+AddressReader.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    public struct AddressReader: OpalBase.Network.AddressQueryClient, OpalBase.Network.AddressSubscriptionClient {
        private let client: Client
        private let timeouts: OpalBase.Network.FulcrumRequestTimeout
        
        public init(client: Client, timeouts: OpalBase.Network.FulcrumRequestTimeout = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func fetchBalance(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> OpalBase.Network.AddressBalance {
            try await OpalBase.Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.address(.getBalance(address: address, tokenFilter: tokenFilter.fulcrumTokenFilter))),
                    responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Address.GetBalance.self,
                    options: .init(timeout: timeouts.addressBalance)
                )
                return OpalBase.Network.AddressBalance(confirmed: result.confirmed, unconfirmed: result.unconfirmed)
            }
        }
        
        public func fetchUnspentOutputs(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> [OpalBase.Transaction.Output.Unspent] {
            try await OpalBase.Network.performWithFailureTranslation {
                let lockingScriptData: Data
                do {
                    lockingScriptData = try OpalBase.Address(address).lockingScript.data
                } catch {
                    throw OpalBase.Network.Error(
                        reason: .protocolViolation,
                        message: "Invalid address provided: \(address)"
                    )
                }
                
                let result = try await client.request(
                    method: .blockchain(.address(.listUnspent(address: address, tokenFilter: tokenFilter.fulcrumTokenFilter))),
                    responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Address.ListUnspent.self,
                    options: .init(timeout: timeouts.addressUnspent)
                )
                
                let unspentOutputs = try result.items.map { item in
                    guard let index = UInt32(exactly: item.transactionPosition) else {
                        throw OpalBase.Network.Error(reason: .decoding, message: "OpalBase.Transaction position overflow")
                    }
                    let hash = try OpalBase.Network.decodeTransactionHash(
                        from: item.transactionHash,
                        label: "unspent transaction hash"
                    )
                    let tokenData = try item.tokenData.map { try OpalBase.CashTokens.TokenData(swiftFulcrumTokenData: $0) }
                    return OpalBase.Transaction.Output.Unspent(
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
        
        public func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
            try await OpalBase.Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(
                        .address(
                            .getHistory(
                                address: address,
                                fromHeight: nil,
                                toHeight: nil,
                                shouldIncludeUnconfirmed: includeUnconfirmed
                            )
                        )
                    ),
                    responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Address.GetHistory.self,
                    options: .init(timeout: timeouts.addressHistory)
                )
                
                return result.transactions.map { transaction in
                    OpalBase.Network.TransactionHistoryEntry(
                        transactionIdentifier: transaction.transactionHash,
                        blockHeight: transaction.height,
                        fee: OpalBase.Network.Fulcrum.resolveFee(transaction.fee)
                    )
                }
            }
        }
        
        public func fetchFirstUse(for address: String) async throws -> OpalBase.Network.AddressFirstUse? {
            try await OpalBase.Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.address(.getFirstUse(address: address))),
                    responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Address.GetFirstUse.self,
                    options: .init(timeout: timeouts.addressFirstUse)
                )
                
                guard let blockHash = result.blockHash,
                      let blockHeight = result.height,
                      let transactionHash = result.transactionHash else {
                    return nil
                }
                
                return OpalBase.Network.AddressFirstUse(blockHeight: blockHeight,
                                       blockHash: blockHash,
                                       transactionIdentifier: transactionHash)
            }
        }
        
        public func fetchMempoolTransactions(for address: String) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
            try await OpalBase.Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.address(.getMempool(address: address))),
                    responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Address.GetMempool.self,
                    options: .init(timeout: timeouts.addressMempool)
                )
                
                return result.transactions.map { transaction in
                    OpalBase.Network.TransactionHistoryEntry(
                        transactionIdentifier: transaction.transactionHash,
                        blockHeight: transaction.height,
                        fee: OpalBase.Network.Fulcrum.resolveFee(transaction.fee)
                    )
                }
            }
        }
        
        public func fetchScriptHash(for address: String) async throws -> String {
            try await OpalBase.Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.address(.getScriptHash(address: address))),
                    responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Address.GetScriptHash.self,
                    options: .init(timeout: timeouts.addressScriptHash)
                )
                return result.scriptHash
            }
        }
        
        public func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, any Swift.Error> {
            try await OpalBase.Network.performWithFailureTranslation {
                let (initial, updates, cancel) = try await client.subscribe(
                    method: .blockchain(.address(.subscribe(address: address))),
                    initial: SwiftFulcrum.RPC.Response.Result.Blockchain.Address.Subscribe.self,
                    notifications: SwiftFulcrum.RPC.Response.Result.Blockchain.Address.SubscribeNotification.self,
                    options: .init(timeout: timeouts.addressSubscription)
                )
                
                let subscribedAddress = address
                return OpalBase.Network.makeSubscriptionStream(
                    initial: initial,
                    updates: updates,
                    cancel: cancel,
                    makeInitialUpdates: { snapshot in
                        [
                            OpalBase.Network.AddressSubscriptionUpdate(
                                kind: .initialSnapshot,
                                address: subscribedAddress,
                                status: snapshot.status
                            )
                        ]
                    },
                    makeUpdates: { notification in
                        guard subscribedAddress == notification.subscriptionIdentifier else { return .init() }
                        return [
                            OpalBase.Network.AddressSubscriptionUpdate(
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
