// OpalBase+Network+Fulcrum+TransactionProofClient_.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    protocol TransactionProofClient: Sendable {
        func fetchTransactionHeight(
            transactionHash: String,
            options: SwiftFulcrum.Client.Call.Options
        ) async throws -> SwiftFulcrum.Response.Blockchain.Transaction.Height
        func fetchTransactionMerkleProof(
            transactionHash: String,
            blockHeight: UInt,
            options: SwiftFulcrum.Client.Call.Options
        ) async throws -> SwiftFulcrum.Response.Blockchain.Transaction.Merkle
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
    ) async throws -> SwiftFulcrum.Response.Blockchain.Transaction.Height {
        try await request(
            SwiftFulcrum.API.blockchain.transaction.height(transactionHash: transactionHash),
            options: options
        )
    }

    func fetchTransactionMerkleProof(
        transactionHash: String,
        blockHeight: UInt,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Blockchain.Transaction.Merkle {
        try await request(
            SwiftFulcrum.API.blockchain.transaction.merkle(transactionHash: transactionHash, height: blockHeight),
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
            SwiftFulcrum.API.blockchain.transaction.idFromPos(
                blockHeight: blockHeight,
                transactionPosition: transactionPosition,
                shouldIncludeMerkleProof: shouldIncludeMerkleProof
            ),
            options: options
        )
    }
}
