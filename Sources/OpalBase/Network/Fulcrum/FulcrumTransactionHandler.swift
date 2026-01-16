// Network+FulcrumTransactionHandler.swift

import Foundation
import SwiftFulcrum

extension Network {
    public struct FulcrumTransactionHandler: TransactionHandling {
        private let client: FulcrumClient
        private let timeouts: FulcrumRequestTimeout
        
        public init(client: FulcrumClient, timeouts: FulcrumRequestTimeout = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func broadcastTransaction(rawTransactionHexadecimal: String) async throws -> String {
            try await Network.withFailureTranslation {
                let response = try await client.request(
                    method: .blockchain(.transaction(.broadcast(rawTransaction: rawTransactionHexadecimal))),
                    responseType: Response.Result.Blockchain.Transaction.Broadcast.self,
                    options: .init(timeout: timeouts.transactionBroadcast)
                )
                return response.transactionHash.hexadecimalString
            }
        }
        
        public func fetchConfirmations(forTransactionIdentifier transactionIdentifier: String) async throws -> UInt? {
            let hash = try Network.decodeTransactionHash(from: transactionIdentifier)
            let status = try await fetchConfirmationStatus(for: hash)
            return status.confirmations
        }
        
        public func fetchConfirmationStatus(for transactionHash: Transaction.Hash) async throws -> Network.TransactionConfirmationStatus {
            let identifier = transactionHash.reverseOrder.hexadecimalString
            
            return try await Network.withFailureTranslation {
                async let transactionHeightResponse = client.request(
                    method: .blockchain(.transaction(.getHeight(transactionHash: identifier))),
                    responseType: Response.Result.Blockchain.Transaction.GetHeight.self,
                    options: .init(timeout: timeouts.transactionConfirmations)
                )
                async let tipHeightResponse = client.request(
                    method: .blockchain(.headers(.getTip)),
                    responseType: Response.Result.Blockchain.Headers.GetTip.self,
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
                
                return Network.TransactionConfirmationStatus(transactionHash: transactionHash,
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
