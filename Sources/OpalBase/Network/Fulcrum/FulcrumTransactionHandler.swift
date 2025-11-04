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
            do {
                let response = try await client.request(
                    method: .blockchain(.transaction(.broadcast(rawTransaction: rawTransactionHexadecimal))),
                    responseType: Response.Result.Blockchain.Transaction.Broadcast.self,
                    options: .init(timeout: timeouts.transactionBroadcast)
                )
                return response.transactionHash.hexadecimalString
            } catch {
                throw FulcrumErrorTranslator.translate(error)
            }
        }
        
        public func fetchConfirmations(forTransactionIdentifier transactionIdentifier: String) async throws -> UInt? {
            do {
                async let transactionHeightResponse = client.request(
                    method: .blockchain(.transaction(.getHeight(transactionHash: transactionIdentifier))),
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
                
                guard transactionHeight > 0 else { return nil }
                if tipHeight < transactionHeight { return 1 }
                
                let confirmationCount = tipHeight - transactionHeight + 1
                return UInt(confirmationCount)
            } catch {
                throw FulcrumErrorTranslator.translate(error)
            }
        }
    }
}
