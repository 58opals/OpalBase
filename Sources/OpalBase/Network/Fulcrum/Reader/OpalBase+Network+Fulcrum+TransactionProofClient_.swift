// OpalBase+Network+Fulcrum+TransactionProofClient_.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    protocol TransactionProofClient: Sendable {
        func fetchTransactionMerkleProof(
            transactionHash: String,
            options: SwiftFulcrum.Client.Call.Options
        ) async throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetMerkle
        func fetchTransactionIdentifier(
            blockHeight: UInt,
            transactionPosition: UInt,
            shouldIncludeMerkleProof: Bool,
            options: SwiftFulcrum.Client.Call.Options
        ) async throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.IDFromPos
    }
}

extension _OpalBase.Network.Fulcrum.Client: _OpalBase.Network.Fulcrum.TransactionProofClient {
    func fetchTransactionMerkleProof(
        transactionHash: String,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetMerkle {
        try await request(
            method: .blockchain(.transaction(.getMerkle(transactionHash: transactionHash))),
            responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetMerkle.self,
            options: options
        )
    }

    func fetchTransactionIdentifier(
        blockHeight: UInt,
        transactionPosition: UInt,
        shouldIncludeMerkleProof: Bool,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.IDFromPos {
        try await request(
            method: .blockchain(
                .transaction(
                    .idFromPos(
                        blockHeight: blockHeight,
                        transactionPosition: transactionPosition,
                        shouldIncludeMerkleProof: shouldIncludeMerkleProof
                    )
                )
            ),
            responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.IDFromPos.self,
            options: options
        )
    }
}
