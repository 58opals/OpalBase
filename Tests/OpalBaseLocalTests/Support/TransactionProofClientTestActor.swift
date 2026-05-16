// TransactionProofClientTestActor.swift

import Foundation
import SwiftFulcrum
@testable import OpalBase

actor TransactionProofClientTestActor: OpalBase.Network.Fulcrum.TransactionProofClient {
    private let merkleResponse: SwiftFulcrum.Response.Blockchain.Transaction.Merkle
    private let heightResponse: SwiftFulcrum.Response.Blockchain.Transaction.Height
    private let identifierResponse: SwiftFulcrum.Response.Blockchain.Transaction.IDFromPos
    private let merkleError: Swift.Error?
    private var requestedTransactionHash: String?
    private var requestedMerkleBlockHeight: UInt?
    private var requestedPositionResolution: (UInt, UInt, Bool)?

    init(
        merkleResponse: SwiftFulcrum.Response.Blockchain.Transaction.Merkle? = nil,
        heightResponse: SwiftFulcrum.Response.Blockchain.Transaction.Height? = nil,
        identifierResponse: SwiftFulcrum.Response.Blockchain.Transaction.IDFromPos? = nil,
        merkleError: Swift.Error? = nil
    ) {
        self.merkleResponse = merkleResponse ?? (try! Self.makeEmptyMerkleResponse())
        self.heightResponse = heightResponse ?? (try! Self.makeHeightResponse(blockHeight: 12))
        self.identifierResponse = identifierResponse ?? (try! Self.makeEmptyIdentifierResponse())
        self.merkleError = merkleError
    }

    func fetchTransactionMerkleProof(
        transactionHash: String,
        blockHeight: UInt,
        options _: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Blockchain.Transaction.Merkle {
        requestedTransactionHash = transactionHash
        requestedMerkleBlockHeight = blockHeight
        if let merkleError {
            throw merkleError
        }
        return merkleResponse
    }

    func fetchTransactionHeight(
        transactionHash _: String,
        options _: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Blockchain.Transaction.Height {
        heightResponse
    }

    func fetchTransactionIdentifier(
        blockHeight: UInt,
        transactionPosition: UInt,
        shouldIncludeMerkleProof: Bool,
        options _: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Blockchain.Transaction.IDFromPos {
        requestedPositionResolution = (blockHeight, transactionPosition, shouldIncludeMerkleProof)
        return identifierResponse
    }

    func readRequestedTransactionHash() -> String? {
        requestedTransactionHash
    }

    func readRequestedMerkleBlockHeight() -> UInt? {
        requestedMerkleBlockHeight
    }

    func readRequestedPositionResolution() -> (UInt, UInt, Bool)? {
        requestedPositionResolution
    }
}

private extension TransactionProofClientTestActor {
    static func makeHeightResponse(blockHeight: UInt) throws -> SwiftFulcrum.Response.Blockchain.Transaction.Height {
        try JSONDecoder().decode(
            SwiftFulcrum.Response.Blockchain.Transaction.Height.self,
            from: Data(String(blockHeight).utf8)
        )
    }

    static func makeEmptyMerkleResponse() throws -> SwiftFulcrum.Response.Blockchain.Transaction.Merkle {
        let payload = try JSONSerialization.data(withJSONObject: ["merkle": [], "block_height": 0, "pos": 0])
        return try JSONDecoder().decode(SwiftFulcrum.Response.Blockchain.Transaction.Merkle.self, from: payload)
    }

    static func makeEmptyIdentifierResponse() throws -> SwiftFulcrum.Response.Blockchain.Transaction.IDFromPos {
        let payload = try JSONSerialization.data(withJSONObject: ["merkle": [], "tx_hash": String(repeating: "0", count: 64)])
        return try JSONDecoder().decode(SwiftFulcrum.Response.Blockchain.Transaction.IDFromPos.self, from: payload)
    }
}
