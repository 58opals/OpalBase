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
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.AddressModel.GetBalanceModel.self,
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
                    throw Network.Error(
                        reason: .protocolViolation,
                        message: "Invalid address provided: \(address)"
                    )
                }
                
                let result = try await client.request(
                    method: .blockchain(.address(.listUnspent(address: address, tokenFilter: tokenFilter))),
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.AddressModel.ListUnspentModel.self,
                    options: .init(timeout: timeouts.addressUnspent)
                )
                
                let unspentOutputs = try result.items.map { item in
                    guard let index = UInt32(exactly: item.transactionPosition) else {
                        throw Network.Error(reason: .decoding, message: "Transaction position overflow")
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
                                shouldIncludeUnconfirmed: includeUnconfirmed
                            )
                        )
                    ),
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.AddressModel.GetHistoryModel.self,
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
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.AddressModel.GetFirstUseModel.self,
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
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.AddressModel.GetMempoolModel.self,
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
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.AddressModel.GetScriptHashModel.self,
                    options: .init(timeout: timeouts.addressScriptHash)
                )
                return result.scriptHash
            }
        }
        
        public func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<AddressSubscriptionUpdate, any Swift.Error> {
            try await Network.performWithFailureTranslation {
                let (initial, updates, cancel) = try await client.subscribe(
                    method: .blockchain(.address(.subscribe(address: address))),
                    initialType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.AddressModel.SubscribeModel.self,
                    notificationType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.AddressModel.SubscribeNotificationModel.self,
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
