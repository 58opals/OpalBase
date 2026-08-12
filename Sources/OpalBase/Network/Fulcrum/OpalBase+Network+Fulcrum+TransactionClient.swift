// OpalBase+Network+Fulcrum+TransactionClient.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    public struct TransactionClient: OpalBase.Network.TransactionBroadcastClient, OpalBase.Network.TransactionConfirmationClient {
        private let client: Client
        private let timeouts: OpalBase.Network.FulcrumRequestTimeout
        let network: OpalBase.Network.Environment
        
        public init(client: Client, timeouts: OpalBase.Network.FulcrumRequestTimeout = .init()) {
            self.client = client
            self.timeouts = timeouts
            network = client.configuration.network
        }
        
        public func broadcastTransaction(rawTransactionHexadecimal: String) async throws -> String {
            let rawTransactionData = try OpalBase.Network.decodeRawTransactionData(from: rawTransactionHexadecimal)
            return try await OpalBase.Network.performWithFailureTranslation {
                let response = try await client.request(
                    SwiftFulcrum.API.blockchain.transaction.broadcast(rawTransaction: rawTransactionHexadecimal),
                    options: .init(timeout: timeouts.transactionBroadcast)
                )
                return try OpalBase.Network.decodeBroadcastTransactionHash(
                    from: response.transactionHash.hexadecimalString,
                    rawTransactionData: rawTransactionData
                ).reverseOrder.hexadecimalString
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
            if height == 0 || height == -1 { return nil }
            guard height > 0 else {
                throw Self.invalidHeightError(label: "transaction height", value: height)
            }
            if let resolved = Int(exactly: height) {
                return resolved
            }
            throw Self.invalidHeightError(label: "transaction height", value: height)
        }
        
        static func resolveTipHeight<Height: BinaryInteger>(_ height: Height) throws -> UInt64 {
            if let resolved = UInt64(exactly: height) {
                return resolved
            }
            throw Self.invalidHeightError(label: "tip height", value: height)
        }

        private static func invalidHeightError<Height: BinaryInteger>(
            label: String,
            value: Height
        ) -> OpalBase.Network.Error {
            OpalBase.Network.Error(reason: .decoding, message: "Invalid \(label): \(value)")
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
        _ historyTransactions: [TransactionValue],
        transactionIdentifier: KeyPath<TransactionValue, String>,
        blockHeight: KeyPath<TransactionValue, Int>,
        fee: KeyPath<TransactionValue, UInt?>
    ) throws -> [OpalBase.Network.TransactionHistoryEntry] {
        try historyTransactions.map { transaction in
            let identifier = transaction[keyPath: transactionIdentifier]
            let transactionHash = try OpalBase.Network.decodeTransactionHash(
                from: identifier,
                label: "history transaction hash"
            )
            let resolvedBlockHeight = transaction[keyPath: blockHeight]
            guard resolvedBlockHeight >= -1 else {
                throw OpalBase.Network.Error(
                    reason: .decoding,
                    message: "Invalid history transaction height: \(resolvedBlockHeight)"
                )
            }
            return OpalBase.Network.TransactionHistoryEntry(
                transactionIdentifier: transactionHash.reverseOrder.hexadecimalString,
                blockHeight: resolvedBlockHeight,
                fee: try resolveFee(transaction[keyPath: fee])
            )
        }
    }

    static func mapMempoolTransactions<TransactionValue>(
        _ mempoolTransactions: [TransactionValue],
        transactionIdentifier: KeyPath<TransactionValue, String>,
        blockHeight: KeyPath<TransactionValue, Int>,
        fee: KeyPath<TransactionValue, UInt?>
    ) throws -> [OpalBase.Network.TransactionHistoryEntry] {
        let entries = try mapHistoryTransactions(
            mempoolTransactions,
            transactionIdentifier: transactionIdentifier,
            blockHeight: blockHeight,
            fee: fee
        )
        for entry in entries where entry.blockHeight > 0 {
            throw OpalBase.Network.Error(
                reason: .protocolViolation,
                message: "Mempool response included a confirmed transaction"
            )
        }
        return entries
    }
}
