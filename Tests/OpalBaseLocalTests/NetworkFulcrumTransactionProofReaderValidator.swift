// NetworkFulcrumTransactionProofReaderValidator.swift

import Foundation
import Testing
import SwiftFulcrum
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.Fulcrum.TransactionProofReader", .tags(.unit, .network))
struct NetworkFulcrumTransactionProofReaderValidator {
    @Test("maps merkle proof and position responses")
    func mapTransactionProofResponsesToOpalBaseTypes() async throws {
        let merkleResponse = try Self.makeMerkleResponse()
        let identifierResponse = try Self.makeIdentifierResponse()
        let client = try TransactionProofClientTestActor(
            merkleResponse: merkleResponse,
            identifierResponse: identifierResponse
        )
        let reader = OpalBase.Network.Fulcrum.TransactionProofReader(client: client)
        let transactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32))

        let merkleProof = try await reader.fetchMerkleProof(for: transactionHash)
        let resolution = try await reader.fetchTransactionIdentifier(atHeight: 12, position: 3, shouldIncludeMerkleProof: true)

        #expect(merkleProof == .init(blockHeight: 12, position: 3, merkle: Self.validMerkleBranch))
        #expect(resolution == .init(
            blockHeight: 12,
            transactionIdentifier: String(repeating: "c", count: 64),
            merkle: [String(repeating: "d", count: 64), String(repeating: "e", count: 64)]
        ))
        #expect(await client.readRequestedTransactionHash() == transactionHash.reverseOrder.hexadecimalString)
        #expect(await client.readRequestedMerkleBlockHeight() == 12)
        let requestedPositionResolution = try #require(await client.readRequestedPositionResolution())
        #expect(requestedPositionResolution.0 == 12)
        #expect(requestedPositionResolution.1 == 3)
        #expect(requestedPositionResolution.2 == true)
    }

    @Test("translates protocol failures for transaction proof requests")
    func fetchMerkleProofTranslatesProtocolFailures() async throws {
        let client = try TransactionProofClientTestActor(
            merkleError: SwiftFulcrum.Client.Error.client(.protocolMismatch("unexpected merkle response"))
        )
        let reader = OpalBase.Network.Fulcrum.TransactionProofReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchMerkleProof(for: .init(naturalOrder: Data(repeating: 0x01, count: 32)))
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == "unexpected merkle response")
    }

    @Test("rejects merkle proof height mismatches")
    func fetchMerkleProofRejectsHeightMismatch() async throws {
        let client = try TransactionProofClientTestActor(
            merkleResponse: try Self.makeMerkleResponse(blockHeight: 13),
            heightResponse: try Self.makeHeightResponse(blockHeight: 12)
        )
        let reader = OpalBase.Network.Fulcrum.TransactionProofReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchMerkleProof(for: .init(naturalOrder: Data(repeating: 0x01, count: 32)))
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message?.contains("Merkle proof block height mismatch") == true)
    }

    @Test("rejects zero-height merkle proof requests")
    func fetchMerkleProofRejectsZeroHeight() async throws {
        let client = try TransactionProofClientTestActor(
            heightResponse: try Self.makeHeightResponse(blockHeight: 0)
        )
        let reader = OpalBase.Network.Fulcrum.TransactionProofReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchMerkleProof(for: .init(naturalOrder: Data(repeating: 0x01, count: 32)))
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == "Merkle proof requires a confirmed transaction height.")
        #expect(await client.readRequestedTransactionHash() == nil)
    }

    @Test("rejects malformed merkle proof branch hashes")
    func fetchMerkleProofRejectsMalformedBranchHashes() async throws {
        let client = try TransactionProofClientTestActor(
            merkleError: Self.makeDecodeError("Expected merkle proof hash to contain only hex characters")
        )
        let reader = OpalBase.Network.Fulcrum.TransactionProofReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchMerkleProof(for: .init(naturalOrder: Data(repeating: 0x01, count: 32)))
        }

        #expect(failure.reason == .decoding)
        #expect(failure.message?.contains("Expected merkle proof hash to contain only hex characters") == true)
    }

    @Test("rejects merkle proof positions outside the branch depth")
    func fetchMerkleProofRejectsPositionOutsideBranchDepth() async throws {
        let client = try TransactionProofClientTestActor(
            merkleResponse: try Self.makeMerkleResponse(merkle: [], position: 1),
            heightResponse: try Self.makeHeightResponse(blockHeight: 12)
        )
        let reader = OpalBase.Network.Fulcrum.TransactionProofReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchMerkleProof(for: .init(naturalOrder: Data(repeating: 0x01, count: 32)))
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message?.contains("Merkle proof position out of range") == true)
    }

    @Test("rejects merkle proof branches too deep to validate")
    func fetchMerkleProofRejectsUnrepresentableBranchDepth() async throws {
        let oversizedBranch = Array(repeating: String(repeating: "a", count: 64), count: UInt.bitWidth)
        let client = try TransactionProofClientTestActor(
            merkleResponse: try Self.makeMerkleResponse(merkle: oversizedBranch, position: 0),
            heightResponse: try Self.makeHeightResponse(blockHeight: 12)
        )
        let reader = OpalBase.Network.Fulcrum.TransactionProofReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchMerkleProof(for: .init(naturalOrder: Data(repeating: 0x01, count: 32)))
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message?.contains("Merkle proof branch length is too large") == true)
    }

    @Test("position resolution skips proof position validation when proof is not requested")
    func resolveTransactionIdentifierWithoutProofPositionValidation() async throws {
        let client = try TransactionProofClientTestActor(
            identifierResponse: try Self.makeIdentifierResponse(merkle: [])
        )
        let reader = OpalBase.Network.Fulcrum.TransactionProofReader(client: client)

        let resolution = try await reader.fetchTransactionIdentifier(
            atHeight: 12,
            position: 1,
            shouldIncludeMerkleProof: false
        )

        #expect(resolution.blockHeight == 12)
        #expect(resolution.merkle.isEmpty)
        let requestedPositionResolution = try #require(await client.readRequestedPositionResolution())
        #expect(requestedPositionResolution.0 == 12)
        #expect(requestedPositionResolution.1 == 1)
        #expect(requestedPositionResolution.2 == false)
    }

    @Test("position resolution rejects proof branches too deep to validate")
    func fetchTransactionIdentifierRejectsUnrepresentableBranchDepth() async throws {
        let oversizedBranch = Array(repeating: String(repeating: "d", count: 64), count: UInt.bitWidth)
        let client = try TransactionProofClientTestActor(
            identifierResponse: try Self.makeIdentifierResponse(merkle: oversizedBranch)
        )
        let reader = OpalBase.Network.Fulcrum.TransactionProofReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchTransactionIdentifier(
                atHeight: 12,
                position: 0,
                shouldIncludeMerkleProof: true
            )
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message?.contains("Merkle proof branch length is too large") == true)
    }

    @Test("rejects malformed transaction identifiers from position resolution")
    func fetchTransactionIdentifierRejectsMalformedIdentifier() async throws {
        let client = try TransactionProofClientTestActor(
            identifierError: Self.makeDecodeError("Expected transaction hash to contain only hex characters")
        )
        let reader = OpalBase.Network.Fulcrum.TransactionProofReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchTransactionIdentifier(
                atHeight: 12,
                position: 3,
                shouldIncludeMerkleProof: true
            )
        }

        #expect(failure.reason == .decoding)
        #expect(failure.message?.contains("Expected transaction hash to contain only hex characters") == true)
    }
}

private extension NetworkFulcrumTransactionProofReaderValidator {
    enum NetworkErrorCaptureFailure: Swift.Error {
        case didNotThrow
        case unexpected(Swift.Error)
    }

    struct DecodeFailure: Swift.Error, CustomStringConvertible {
        let description: String
    }

    static let validMerkleBranch = [String(repeating: "a", count: 64), String(repeating: "b", count: 64)]

    static func makeDecodeError(_ message: String) -> SwiftFulcrum.Client.Error {
        .coding(.decode(DecodeFailure(description: ".unexpectedFormat(\"\(message)\")")))
    }

    static func makeMerkleResponse(
        merkle: [String] = validMerkleBranch,
        position: UInt = 3
    ) throws -> SwiftFulcrum.Response.Blockchain.Transaction.Merkle {
        try makeMerkleResponse(blockHeight: 12, merkle: merkle, position: position)
    }

    static func makeMerkleResponse(
        blockHeight: UInt,
        merkle: [String] = validMerkleBranch,
        position: UInt = 3
    ) throws -> SwiftFulcrum.Response.Blockchain.Transaction.Merkle {
        let payload = try JSONSerialization.data(withJSONObject: ["merkle": merkle, "block_height": blockHeight, "pos": position])
        return try JSONDecoder().decode(SwiftFulcrum.Response.Blockchain.Transaction.Merkle.self, from: payload)
    }

    static func makeHeightResponse(blockHeight: UInt) throws -> SwiftFulcrum.Response.Blockchain.Transaction.Height {
        try JSONDecoder().decode(
            SwiftFulcrum.Response.Blockchain.Transaction.Height.self,
            from: Data(String(blockHeight).utf8)
        )
    }

    static func makeIdentifierResponse(
        transactionHash: String = String(repeating: "c", count: 64),
        merkle: [String] = [String(repeating: "d", count: 64), String(repeating: "e", count: 64)]
    ) throws -> SwiftFulcrum.Response.Blockchain.Transaction.IDFromPos {
        let payload = try JSONSerialization.data(
            withJSONObject: ["merkle": merkle, "tx_hash": transactionHash]
        )
        return try JSONDecoder().decode(SwiftFulcrum.Response.Blockchain.Transaction.IDFromPos.self, from: payload)
    }

    static func makeEmptyMerkleResponse() throws -> SwiftFulcrum.Response.Blockchain.Transaction.Merkle {
        let payload = try JSONSerialization.data(withJSONObject: ["merkle": [], "block_height": 0, "pos": 0])
        return try JSONDecoder().decode(SwiftFulcrum.Response.Blockchain.Transaction.Merkle.self, from: payload)
    }

    static func makeEmptyIdentifierResponse() throws -> SwiftFulcrum.Response.Blockchain.Transaction.IDFromPos {
        let payload = try JSONSerialization.data(withJSONObject: ["merkle": [], "tx_hash": String(repeating: "0", count: 64)])
        return try JSONDecoder().decode(SwiftFulcrum.Response.Blockchain.Transaction.IDFromPos.self, from: payload)
    }

    static func captureNetworkError(
        _ work: () async throws -> Void
    ) async throws -> OpalBase.Network.Error {
        do {
            try await work()
            throw NetworkErrorCaptureFailure.didNotThrow
        } catch let failure as OpalBase.Network.Error {
            return failure
        } catch let failure as NetworkErrorCaptureFailure {
            throw failure
        } catch {
            throw NetworkErrorCaptureFailure.unexpected(error)
        }
    }
}
