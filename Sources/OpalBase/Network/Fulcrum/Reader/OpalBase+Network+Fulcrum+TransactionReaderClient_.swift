import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    protocol TransactionReaderClient: Sendable {
        func fetchRawTransaction(
            transactionHash: String,
            options: SwiftFulcrum.Client.Call.Options
        ) async throws -> String
        func fetchVerboseTransaction(
            transactionHash: String,
            options: SwiftFulcrum.Client.Call.Options
        ) async throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.Get
    }
}

extension _OpalBase.Network.Fulcrum.Client: _OpalBase.Network.Fulcrum.TransactionReaderClient {
    func fetchRawTransaction(
        transactionHash: String,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> String {
        try await request(
            method: .blockchain(.transaction(.get(transactionHash: transactionHash, isVerbose: false))),
            responseType: String.self,
            options: options
        )
    }

    func fetchVerboseTransaction(
        transactionHash: String,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.Get {
        try await request(
            method: .blockchain(.transaction(.get(transactionHash: transactionHash, isVerbose: true))),
            responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.Get.self,
            options: options
        )
    }
}
