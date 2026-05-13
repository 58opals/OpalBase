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
                _ = try validateAddress(address)
                let result = try await client.request(
                    .blockchain.address.getBalance(address: address, tokenFilter: tokenFilter.fulcrumTokenFilter),
                    options: .init(timeout: timeouts.addressBalance)
                )
                return OpalBase.Network.AddressBalance(confirmed: result.confirmed, unconfirmed: result.unconfirmed)
            }
        }
        
        public func fetchUnspentOutputs(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> [OpalBase.Transaction.Output.Unspent] {
            try await OpalBase.Network.performWithFailureTranslation {
                let lockingScriptData = try validateAddress(address).lockingScript.data
                
                let result = try await client.request(
                    .blockchain.address.listUnspent(address: address, tokenFilter: tokenFilter.fulcrumTokenFilter),
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
                _ = try validateAddress(address)
                let result = try await client.request(
                    .blockchain.address.getHistory(
                        address: address,
                        shouldIncludeUnconfirmed: includeUnconfirmed
                    ),
                    options: .init(timeout: timeouts.addressHistory)
                )
                
                return try OpalBase.Network.Fulcrum.mapHistoryTransactions(
                    result.transactions,
                    transactionIdentifier: \.transactionHash,
                    blockHeight: \.height,
                    fee: \.fee
                )
            }
        }
        
        public func fetchFirstUse(for address: String) async throws -> OpalBase.Network.AddressFirstUse? {
            try await OpalBase.Network.performWithFailureTranslation {
                _ = try validateAddress(address)
                let result = try await client.request(
                    .blockchain.address.getFirstUse(address: address),
                    options: .init(timeout: timeouts.addressFirstUse)
                )
                
                return try Self.makeFirstUse(
                    blockHeight: result.height,
                    blockHash: result.blockHash,
                    transactionIdentifier: result.transactionHash
                )
            }
        }
        
        public func fetchMempoolTransactions(for address: String) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
            try await OpalBase.Network.performWithFailureTranslation {
                _ = try validateAddress(address)
                let result = try await client.request(
                    .blockchain.address.getMempool(address: address),
                    options: .init(timeout: timeouts.addressMempool)
                )
                
                return try OpalBase.Network.Fulcrum.mapHistoryTransactions(
                    result.transactions,
                    transactionIdentifier: \.transactionHash,
                    blockHeight: \.height,
                    fee: \.fee
                )
            }
        }
        
        public func fetchScriptHash(for address: String) async throws -> String {
            try await OpalBase.Network.performWithFailureTranslation {
                let validatedAddress = try validateAddress(address)
                let result = try await client.request(
                    .blockchain.address.getScriptHash(address: address),
                    options: .init(timeout: timeouts.addressScriptHash)
                )
                return try Self.validateScriptHash(result.scriptHash, matches: validatedAddress)
            }
        }
        
        public func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, any Swift.Error> {
            try await OpalBase.Network.performWithFailureTranslation {
                _ = try validateAddress(address)
                let (initial, updates, cancel) = try await client.subscribe(
                    .blockchain.address.subscribe(address: address),
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
        
        static func makeFirstUse(
            blockHeight: UInt?,
            blockHash: String?,
            transactionIdentifier: String?
        ) throws -> OpalBase.Network.AddressFirstUse? {
            guard blockHeight != nil || blockHash != nil || transactionIdentifier != nil else {
                return nil
            }
            guard let blockHeight, let blockHash, let transactionIdentifier else {
                throw OpalBase.Network.Error(
                    reason: .protocolViolation,
                    message: "Incomplete first-use response"
                )
            }
            return try makeFirstUse(
                blockHeight: blockHeight,
                blockHash: blockHash,
                transactionIdentifier: transactionIdentifier
            )
        }
        
        static func makeFirstUse(
            blockHeight: UInt,
            blockHash: String,
            transactionIdentifier: String
        ) throws -> OpalBase.Network.AddressFirstUse {
            _ = try OpalBase.Network.decodeHashData(from: blockHash, label: "first-use block hash")
            
            _ = try OpalBase.Network.decodeTransactionHash(
                from: transactionIdentifier,
                label: "first-use transaction hash"
            )
            
            return OpalBase.Network.AddressFirstUse(
                blockHeight: blockHeight,
                blockHash: blockHash,
                transactionIdentifier: transactionIdentifier
            )
        }
        
        static func validateScriptHash(_ scriptHash: String) throws -> String {
            _ = try OpalBase.Network.decodeHashData(from: scriptHash, label: "script hash")
            return scriptHash
        }

        static func validateScriptHash(_ scriptHash: String, matches address: OpalBase.Address) throws -> String {
            let validatedScriptHash = try validateScriptHash(scriptHash)
            let expectedScriptHash = address.makeScriptHash().hexadecimalString
            guard validatedScriptHash.caseInsensitiveCompare(expectedScriptHash) == .orderedSame else {
                throw OpalBase.Network.Error(
                    reason: .protocolViolation,
                    message: "Address script hash mismatch",
                    metadata: [
                        "expected": expectedScriptHash,
                        "actual": validatedScriptHash
                    ]
                )
            }
            return validatedScriptHash
        }

        private func validateAddress(_ address: String) throws -> OpalBase.Address {
            do {
                return try OpalBase.Address(
                    string: address,
                    network: client.configuration.network
                )
            } catch {
                throw OpalBase.Network.Error(
                    reason: .protocolViolation,
                    message: "Invalid address provided: \(address)"
                )
            }
        }
    }
}
