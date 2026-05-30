// OpalBase+Network+Fulcrum+TransactionClient.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    public struct TransactionClient: OpalBase.Network.TransactionBroadcastClient, OpalBase.Network.TransactionConfirmationClient {
        private let client: Client
        private let timeouts: OpalBase.Network.FulcrumRequestTimeout
        
        public init(client: Client, timeouts: OpalBase.Network.FulcrumRequestTimeout = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func broadcastTransaction(rawTransactionHexadecimal: String) async throws -> String {
            try await OpalBase.Network.performWithFailureTranslation {
                let response = try await client.request(
                    SwiftFulcrum.API.blockchain.transaction.broadcast(rawTransaction: rawTransactionHexadecimal),
                    options: .init(timeout: timeouts.transactionBroadcast)
                )
                return response.transactionHash.hexadecimalString
            }
        }
        
        public func fetchConfirmations(forTransactionIdentifier transactionIdentifier: String) async throws -> UInt? {
            let hash = try OpalBase.Network.decodeTransactionHash(from: transactionIdentifier)
            let status = try await fetchConfirmationStatus(for: hash)
            return status.confirmations
        }
        
        public func fetchConfirmationStatus(for transactionHash: OpalBase.Transaction.Hash) async throws -> OpalBase.Network.TransactionConfirmationStatus {
            let identifier = transactionHash.reverseOrder.hexadecimalString
            
            return try await OpalBase.Network.performWithFailureTranslation {
                async let transactionHeightResponse = client.request(
                    SwiftFulcrum.API.blockchain.transaction.height(transactionHash: identifier),
                    options: .init(timeout: timeouts.transactionConfirmations)
                )
                async let tipHeightResponse = client.request(
                    SwiftFulcrum.API.blockchain.headers.tip,
                    options: .init(timeout: timeouts.headersTip)
                )
                
                let transactionHeightResult = try await transactionHeightResponse
                let tipHeightResult = try await tipHeightResponse
                
                let transactionHeight = transactionHeightResult.height
                let tipHeight = tipHeightResult.height
                
                return try Self.makeConfirmationStatus(
                    transactionHash: transactionHash,
                    transactionHeight: transactionHeight,
                    tipHeight: tipHeight
                )
            }
        }

        static func makeConfirmationStatus<Height: BinaryInteger>(
            transactionHash: OpalBase.Transaction.Hash,
            transactionHeight: Height?,
            tipHeight: Height
        ) throws -> OpalBase.Network.TransactionConfirmationStatus {
            let resolvedHeight = try Self.resolveTransactionHeight(transactionHeight)
            let resolvedTipHeight = try Self.resolveTipHeight(tipHeight)
            
            if let resolvedHeight, UInt64(resolvedHeight) > resolvedTipHeight {
                throw OpalBase.Network.Error(
                    reason: .protocolViolation,
                    message: "Transaction height exceeds tip height: transaction \(resolvedHeight), tip \(resolvedTipHeight)"
                )
            }
            let confirmationCount = resolvedHeight.map { resolvedHeight in
                UInt(resolvedTipHeight - UInt64(resolvedHeight) + 1)
            }
            
            return OpalBase.Network.TransactionConfirmationStatus(
                transactionHash: transactionHash,
                transactionHeight: resolvedHeight,
                tipHeight: resolvedTipHeight,
                confirmations: confirmationCount
            )
        }
        
        static func resolveTransactionHeight<Height: BinaryInteger>(_ height: Height?) throws -> Int? {
            guard let height else { return nil }
            guard height > 0 else { return nil }
            if let resolved = Int(exactly: height) {
                return resolved
            }
            throw OpalBase.Network.Error(
                reason: .decoding,
                message: "Invalid transaction height: \(height)"
            )
        }
        
        static func resolveTipHeight<Height: BinaryInteger>(_ height: Height) throws -> UInt64 {
            if let resolved = UInt64(exactly: height) {
                return resolved
            }
            throw OpalBase.Network.Error(
                reason: .decoding,
                message: "Invalid tip height: \(height)"
            )
        }
    }
}

extension _OpalBase.Network.Fulcrum {
    static func resolveFee<Fee: BinaryInteger>(_ fee: Fee?) throws -> UInt64? {
        guard let fee else { return nil }
        guard let resolved = UInt64(exactly: fee),
              resolved <= OpalBase.Satoshi.maximumSatoshi else {
            throw OpalBase.Network.Error(
                reason: .decoding,
                message: "Invalid transaction fee: \(fee)"
            )
        }
        return resolved
    }
    
    static func mapHistoryTransactions<TransactionValue>(
        _ transactions: [TransactionValue],
        transactionIdentifier: KeyPath<TransactionValue, String>,
        blockHeight: KeyPath<TransactionValue, Int>,
        fee: KeyPath<TransactionValue, UInt?>
    ) throws -> [OpalBase.Network.TransactionHistoryEntry] {
        try transactions.map { transaction in
            let identifier = transaction[keyPath: transactionIdentifier]
            _ = try OpalBase.Network.decodeTransactionHash(
                from: identifier,
                label: "history transaction hash"
            )
            return OpalBase.Network.TransactionHistoryEntry(
                transactionIdentifier: identifier,
                blockHeight: transaction[keyPath: blockHeight],
                fee: try resolveFee(transaction[keyPath: fee])
            )
        }
    }
}
