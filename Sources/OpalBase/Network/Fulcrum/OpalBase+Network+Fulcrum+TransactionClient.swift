// OpalBase+Network+Fulcrum+TransactionClient.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    public struct TransactionClient: OpalBase.Network.TransactionHandling {
        private let client: Client
        private let timeouts: OpalBase.Network.FulcrumRequestTimeoutModel
        
        public init(client: Client, timeouts: OpalBase.Network.FulcrumRequestTimeoutModel = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func broadcastTransaction(rawTransactionHexadecimal: String) async throws -> String {
            try await OpalBase.Network.performWithFailureTranslation {
                let response = try await client.request(
                    method: .blockchain(.transaction(.broadcast(rawTransaction: rawTransactionHexadecimal))),
                    responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.Broadcast.self,
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
        
        public func fetchConfirmationStatus(for transactionHash: OpalBase.Transaction.HashModel) async throws -> OpalBase.Network.TransactionConfirmationStatus {
            let identifier = transactionHash.reverseOrder.hexadecimalString
            
            return try await OpalBase.Network.performWithFailureTranslation {
                async let transactionHeightResponse = client.request(
                    method: .blockchain(.transaction(.getHeight(transactionHash: identifier))),
                    responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetHeight.self,
                    options: .init(timeout: timeouts.transactionConfirmations)
                )
                async let tipHeightResponse = client.request(
                    method: .blockchain(.headers(.getTip)),
                    responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Headers.GetTip.self,
                    options: .init(timeout: timeouts.headersTip)
                )
                
                let transactionHeightResult = try await transactionHeightResponse
                let tipHeightResult = try await tipHeightResponse
                
                let transactionHeight = transactionHeightResult.height
                let tipHeight = tipHeightResult.height
                
                let confirmationCount = Self.calculateConfirmationCount(
                    transactionHeight: transactionHeight,
                    tipHeight: tipHeight
                )
                
                let resolvedHeight = Self.resolveTransactionHeight(transactionHeight)
                let resolvedTipHeight = Self.resolveTipHeight(tipHeight)
                
                return OpalBase.Network.TransactionConfirmationStatus(transactionHash: transactionHash,
                                                             transactionHeight: resolvedHeight,
                                                             tipHeight: resolvedTipHeight,
                                                             confirmations: confirmationCount)
            }
        }
        
        static func calculateConfirmationCount<Height: BinaryInteger>(
            transactionHeight: Height,
            tipHeight: Height
        ) -> UInt? {
            guard transactionHeight >= 0 else { return nil }
            guard tipHeight >= transactionHeight else { return nil }
            
            let confirmationCount = tipHeight - transactionHeight + 1
            return UInt(confirmationCount)
        }
        
        private static func resolveTransactionHeight<Height: BinaryInteger>(_ height: Height) -> Int? {
            guard height >= 0 else { return nil }
            if let resolved = Int(exactly: height) {
                return resolved
            }
            return Int.max
        }
        
        private static func resolveTipHeight<Height: BinaryInteger>(_ height: Height) -> UInt64 {
            if let resolved = UInt64(exactly: height) {
                return resolved
            }
            if height < 0 { return 0 }
            return UInt64.max
        }
    }
}

extension _OpalBase.Network.Fulcrum {
    static func resolveFee<Fee: BinaryInteger>(_ fee: Fee?) -> UInt64? {
        guard let fee else { return nil }
        return UInt64(exactly: fee)
    }
    
    static func mapHistoryTransactions<TransactionValue>(
        _ transactions: [TransactionValue],
        transactionIdentifier: KeyPath<TransactionValue, String>,
        blockHeight: KeyPath<TransactionValue, Int>,
        fee: KeyPath<TransactionValue, UInt?>
    ) -> [OpalBase.Network.TransactionHistoryEntry] {
        transactions.map { transaction in
            OpalBase.Network.TransactionHistoryEntry(
                transactionIdentifier: transaction[keyPath: transactionIdentifier],
                blockHeight: transaction[keyPath: blockHeight],
                fee: resolveFee(transaction[keyPath: fee])
            )
        }
    }
}
