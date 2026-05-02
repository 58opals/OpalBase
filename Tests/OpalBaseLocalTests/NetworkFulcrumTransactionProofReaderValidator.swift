// NetworkFulcrumTransactionProofReaderValidator.swift

import Foundation
import Testing
import SwiftFulcrum
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.Fulcrum.TransactionProofReader", .tags(.unit, .network))
struct NetworkFulcrumTransactionProofReaderValidator {
    @Test("maps merkle proof and position responses")
    func fetchTransactionProofResponsesMapToOpalBaseTypes() async throws {
        let merkleResponse = try Self.makeMerkleResponse()
        let identifierResponse = try Self.makeIdentifierResponse()
        let client = TransactionProofClientTestActor(
            merkleResponse: merkleResponse,
            identifierResponse: identifierResponse
        )
        let reader = OpalBase.Network.Fulcrum.TransactionProofReader(client: client)
        let transactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32))

        let merkleProof = try await reader.fetchMerkleProof(for: transactionHash)
        let resolution = try await reader.fetchTransactionIdentifier(atHeight: 12, position: 3, shouldIncludeMerkleProof: true)

        #expect(merkleProof == .init(blockHeight: 12, position: 3, merkle: ["aa", "bb"]))
        #expect(resolution == .init(blockHeight: 12, transactionIdentifier: String(repeating: "c", count: 64), merkle: ["dd"]))
        #expect(await client.readRequestedTransactionHash() == transactionHash.reverseOrder.hexadecimalString)
        #expect(await client.readRequestedMerkleBlockHeight() == 12)
        let requestedPositionResolution = try #require(await client.readRequestedPositionResolution())
        #expect(requestedPositionResolution.0 == 12)
        #expect(requestedPositionResolution.1 == 3)
        #expect(requestedPositionResolution.2 == true)
    }

    @Test("translates protocol failures for transaction proof requests")
    func fetchMerkleProofTranslatesProtocolFailures() async throws {
        let client = TransactionProofClientTestActor(
            merkleError: SwiftFulcrum.Client.Error.client(.protocolMismatch("unexpected merkle response"))
        )
        let reader = OpalBase.Network.Fulcrum.TransactionProofReader(client: client)

        let failure = await Self.captureNetworkError {
            _ = try await reader.fetchMerkleProof(for: .init(naturalOrder: Data(repeating: 0x01, count: 32)))
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == "unexpected merkle response")
    }

    @Test("rejects merkle proof height mismatches")
    func fetchMerkleProofRejectsHeightMismatch() async throws {
        let client = TransactionProofClientTestActor(
            merkleResponse: try Self.makeMerkleResponse(blockHeight: 13),
            heightResponse: try Self.makeHeightResponse(blockHeight: 12)
        )
        let reader = OpalBase.Network.Fulcrum.TransactionProofReader(client: client)

        let failure = await Self.captureNetworkError {
            _ = try await reader.fetchMerkleProof(for: .init(naturalOrder: Data(repeating: 0x01, count: 32)))
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message?.contains("Merkle proof block height mismatch") == true)
    }
}

private actor TransactionProofClientTestActor: OpalBase.Network.Fulcrum.TransactionProofClient {
    private let merkleResponse: SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetMerkle
    private let heightResponse: SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetHeight
    private let identifierResponse: SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.IDFromPos
    private let merkleError: Swift.Error?
    private var requestedTransactionHash: String?
    private var requestedMerkleBlockHeight: UInt?
    private var requestedPositionResolution: (UInt, UInt, Bool)?

    init(
        merkleResponse: SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetMerkle? = nil,
        heightResponse: SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetHeight? = nil,
        identifierResponse: SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.IDFromPos? = nil,
        merkleError: Swift.Error? = nil
    ) {
        self.merkleResponse = merkleResponse ?? (try! NetworkFulcrumTransactionProofReaderValidator.makeEmptyMerkleResponse())
        self.heightResponse = heightResponse ?? (try! NetworkFulcrumTransactionProofReaderValidator.makeHeightResponse(blockHeight: 12))
        self.identifierResponse = identifierResponse ?? (try! NetworkFulcrumTransactionProofReaderValidator.makeEmptyIdentifierResponse())
        self.merkleError = merkleError
    }

    func fetchTransactionMerkleProof(
        transactionHash: String,
        blockHeight: UInt,
        options _: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetMerkle {
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
    ) async throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetHeight {
        heightResponse
    }

    func fetchTransactionIdentifier(
        blockHeight: UInt,
        transactionPosition: UInt,
        shouldIncludeMerkleProof: Bool,
        options _: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.IDFromPos {
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

private extension NetworkFulcrumTransactionProofReaderValidator {
    static func makeMerkleResponse() throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetMerkle {
        try makeMerkleResponse(blockHeight: 12)
    }

    static func makeMerkleResponse(blockHeight: UInt) throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetMerkle {
        let payload = try JSONSerialization.data(withJSONObject: ["merkle": ["aa", "bb"], "block_height": blockHeight, "pos": 3])
        return try JSONDecoder().decode(SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetMerkle.self, from: payload)
    }

    static func makeHeightResponse(blockHeight: UInt) throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetHeight {
        try JSONDecoder().decode(
            SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetHeight.self,
            from: Data(String(blockHeight).utf8)
        )
    }

    static func makeIdentifierResponse() throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.IDFromPos {
        let payload = try JSONSerialization.data(withJSONObject: ["merkle": ["dd"], "tx_hash": String(repeating: "c", count: 64)])
        return try JSONDecoder().decode(SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.IDFromPos.self, from: payload)
    }

    static func makeEmptyMerkleResponse() throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetMerkle {
        let payload = try JSONSerialization.data(withJSONObject: ["merkle": [], "block_height": 0, "pos": 0])
        return try JSONDecoder().decode(SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetMerkle.self, from: payload)
    }

    static func makeEmptyIdentifierResponse() throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.IDFromPos {
        let payload = try JSONSerialization.data(withJSONObject: ["merkle": [], "tx_hash": String(repeating: "0", count: 64)])
        return try JSONDecoder().decode(SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.IDFromPos.self, from: payload)
    }

    static func captureNetworkError(
        _ work: () async throws -> Void
    ) async -> OpalBase.Network.Error {
        do {
            try await work()
            Issue.record("Expected OpalBase.Network.Error")
            return .init(reason: .unknown)
        } catch let failure as OpalBase.Network.Error {
            return failure
        } catch {
            Issue.record("Unexpected error: \(error)")
            return .init(reason: .unknown, message: String(describing: error))
        }
    }
}
