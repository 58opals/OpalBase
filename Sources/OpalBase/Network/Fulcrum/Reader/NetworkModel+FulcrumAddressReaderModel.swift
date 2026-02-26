// NetworkModel+FulcrumAddressReaderModel.swift

import Foundation
import SwiftFulcrum

extension NetworkModel {
    public struct FulcrumAddressReaderModel: AddressReadable {
        private let client: FulcrumClient
        private let timeouts: FulcrumRequestTimeoutModel
        
        public init(client: FulcrumClient, timeouts: FulcrumRequestTimeoutModel = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func fetchBalance(for address: String, tokenFilter: NetworkModel.TokenFilter) async throws -> AddressBalanceModel {
            try await NetworkModel.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.address(.getBalance(address: address, tokenFilter: tokenFilter))),
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.AddressModel.GetBalanceModel.self,
                    options: .init(timeout: timeouts.addressBalance)
                )
                return AddressBalanceModel(confirmed: result.confirmed, unconfirmed: result.unconfirmed)
            }
        }
        
        public func fetchUnspentOutputs(for address: String, tokenFilter: NetworkModel.TokenFilter) async throws -> [TransactionModel.OutputModel.UnspentModel] {
            try await NetworkModel.performWithFailureTranslation {
                let lockingScriptData: Data
                do {
                    lockingScriptData = try AddressModel(address).lockingScript.data
                } catch {
                    throw NetworkModel.Error(
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
                        throw NetworkModel.Error(reason: .decoding, message: "TransactionModel position overflow")
                    }
                    let data = try Data(hexadecimalString: item.transactionHash)
                    let hash = TransactionModel.HashModel(dataFromRPC: data)
                    let tokenData = try item.tokenData.map { try CashTokensModel.TokenData(swiftFulcrumTokenData: $0) }
                    return TransactionModel.OutputModel.UnspentModel(
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
        
        public func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [TransactionHistoryEntryModel] {
            try await NetworkModel.performWithFailureTranslation {
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
                    TransactionHistoryEntryModel(
                        transactionIdentifier: transaction.transactionHash,
                        blockHeight: transaction.height,
                        fee: NetworkModel.resolveFee(transaction.fee)
                    )
                }
            }
        }
        
        public func fetchFirstUse(for address: String) async throws -> AddressFirstUseModel? {
            try await NetworkModel.performWithFailureTranslation {
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
                
                return AddressFirstUseModel(blockHeight: blockHeight,
                                       blockHash: blockHash,
                                       transactionIdentifier: transactionHash)
            }
        }
        
        public func fetchMempoolTransactions(for address: String) async throws -> [TransactionHistoryEntryModel] {
            try await NetworkModel.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.address(.getMempool(address: address))),
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.AddressModel.GetMempoolModel.self,
                    options: .init(timeout: timeouts.addressMempool)
                )
                
                return result.transactions.map { transaction in
                    TransactionHistoryEntryModel(
                        transactionIdentifier: transaction.transactionHash,
                        blockHeight: transaction.height,
                        fee: NetworkModel.resolveFee(transaction.fee)
                    )
                }
            }
        }
        
        public func fetchScriptHash(for address: String) async throws -> String {
            try await NetworkModel.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.address(.getScriptHash(address: address))),
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.AddressModel.GetScriptHashModel.self,
                    options: .init(timeout: timeouts.addressScriptHash)
                )
                return result.scriptHash
            }
        }
        
        public func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<AddressSubscriptionUpdateModel, any Swift.Error> {
            try await NetworkModel.performWithFailureTranslation {
                let (initial, updates, cancel) = try await client.subscribe(
                    method: .blockchain(.address(.subscribe(address: address))),
                    initialType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.AddressModel.SubscribeModel.self,
                    notificationType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.AddressModel.SubscribeNotificationModel.self,
                    options: .init(timeout: timeouts.addressSubscription)
                )
                
                let subscribedAddress = address
                return NetworkModel.makeSubscriptionStream(
                    initial: initial,
                    updates: updates,
                    cancel: cancel,
                    makeInitialUpdates: { snapshot in
                        [
                            AddressSubscriptionUpdateModel(
                                kind: .initialSnapshot,
                                address: subscribedAddress,
                                status: snapshot.status
                            )
                        ]
                    },
                    makeUpdates: { notification in
                        guard subscribedAddress == notification.subscriptionIdentifier else { return .init() }
                        return [
                            AddressSubscriptionUpdateModel(
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
