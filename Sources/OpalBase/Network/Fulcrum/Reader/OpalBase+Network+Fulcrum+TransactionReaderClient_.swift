// OpalBase+Network+Fulcrum+TransactionReaderClient_.swift

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
        ) async throws -> SwiftFulcrum.Response.Blockchain.Transaction.Get
    }
}

extension _OpalBase.Network.Fulcrum.Client: _OpalBase.Network.Fulcrum.TransactionReaderClient {
    func fetchRawTransaction(
        transactionHash: String,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> String {
        try await request(
            .blockchain.transaction.get(transactionHash: transactionHash),
            options: options
        )
    }

    func fetchVerboseTransaction(
        transactionHash: String,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Blockchain.Transaction.Get {
        try await request(
            .blockchain.transaction.getVerbose(transactionHash: transactionHash),
            options: options
        )
    }
}
