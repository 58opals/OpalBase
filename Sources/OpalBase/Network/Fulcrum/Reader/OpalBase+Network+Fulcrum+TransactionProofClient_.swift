// OpalBase+Network+Fulcrum+TransactionProofClient_.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    protocol TransactionProofClient: Sendable {
        func fetchTransactionHeight(
            transactionHash: String,
            options: SwiftFulcrum.Client.Call.Options
        ) async throws -> SwiftFulcrum.Response.Blockchain.Transaction.GetHeight
        func fetchTransactionMerkleProof(
            transactionHash: String,
            blockHeight: UInt,
            options: SwiftFulcrum.Client.Call.Options
        ) async throws -> SwiftFulcrum.Response.Blockchain.Transaction.GetMerkle
        func fetchTransactionIdentifier(
            blockHeight: UInt,
            transactionPosition: UInt,
            shouldIncludeMerkleProof: Bool,
            options: SwiftFulcrum.Client.Call.Options
        ) async throws -> SwiftFulcrum.Response.Blockchain.Transaction.IDFromPos
    }
}

extension _OpalBase.Network.Fulcrum.Client: _OpalBase.Network.Fulcrum.TransactionProofClient {
    func fetchTransactionHeight(
        transactionHash: String,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Blockchain.Transaction.GetHeight {
        try await request(
            .blockchain.transaction.getHeight(transactionHash: transactionHash),
            options: options
        )
    }

    func fetchTransactionMerkleProof(
        transactionHash: String,
        blockHeight: UInt,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Blockchain.Transaction.GetMerkle {
        try await request(
            .blockchain.transaction.getMerkle(transactionHash: transactionHash, height: blockHeight),
            options: options
        )
    }

    func fetchTransactionIdentifier(
        blockHeight: UInt,
        transactionPosition: UInt,
        shouldIncludeMerkleProof: Bool,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Blockchain.Transaction.IDFromPos {
        try await request(
            .blockchain.transaction.idFromPos(
                blockHeight: blockHeight,
                transactionPosition: transactionPosition,
                shouldIncludeMerkleProof: shouldIncludeMerkleProof
            ),
            options: options
        )
    }
}
