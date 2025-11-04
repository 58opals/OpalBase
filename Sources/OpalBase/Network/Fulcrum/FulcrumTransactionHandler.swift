// Network+FulcrumTransactionHandler.swift

import Foundation
import SwiftFulcrum

extension Network {
    public struct FulcrumTransactionHandler: TransactionHandling {
        private let client: FulcrumClient
        private let timeouts: FulcrumRequestTimeouts

        public init(client: FulcrumClient, timeouts: FulcrumRequestTimeouts = .init()) {
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
                throw NetworkFulcrumErrorTranslator.translate(error)
            }
        }

        public func fetchConfirmations(forTransactionIdentifier transactionIdentifier: String) async throws -> UInt? {
            do {
                let response = try await client.request(
                    method: .blockchain(.transaction(.getHeight(transactionHash: transactionIdentifier))),
                    responseType: Response.Result.Blockchain.Transaction.GetHeight.self,
                    options: .init(timeout: timeouts.transactionConfirmations)
                )
                return response.height == 0 ? nil : response.height
            } catch {
                throw NetworkFulcrumErrorTranslator.translate(error)
            }
        }
    }
}
