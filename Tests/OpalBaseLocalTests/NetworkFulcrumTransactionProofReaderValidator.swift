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

    @Test("rejects oversized merkle proof branch hashes")
    func merkleResponseRejectsOversizedBranchHashes() throws {
        let failure = try Self.captureError {
            _ = try Self.makeMerkleResponse(
                merkle: [String(repeating: "a", count: 4_096)],
                position: 0
            )
        }

        #expect(String(describing: failure).contains("Expected merkle proof hash to be exactly 64 hex characters"))
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

    @Test("rejects proof branches too deep to validate", arguments: OversizedMerkleBranchRequest.allCases)
    fileprivate func rejectUnrepresentableMerkleBranchDepth(_ request: OversizedMerkleBranchRequest) async throws {
        let client = try request.makeClient()
        let reader = OpalBase.Network.Fulcrum.TransactionProofReader(client: client)

        let failure = try await Self.captureNetworkError {
            try await request.fetch(using: reader)
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

    @Test("rejects unrequested merkle proofs from position resolution")
    func fetchTransactionIdentifierRejectsUnrequestedMerkleProofs() async throws {
        let client = try TransactionProofClientTestActor(
            identifierResponse: try Self.makeIdentifierResponse()
        )
        let reader = OpalBase.Network.Fulcrum.TransactionProofReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchTransactionIdentifier(
                atHeight: 12,
                position: 1,
                shouldIncludeMerkleProof: false
            )
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == "Position resolution returned an unrequested merkle proof.")
    }

    @Test("rejects zero-height proof requests before dependent calls", arguments: ZeroHeightProofRequest.allCases)
    fileprivate func rejectZeroHeightProofRequestsBeforeDependentCalls(
        _ request: ZeroHeightProofRequest
    ) async throws {
        let client = try request.makeClient()
        let reader = OpalBase.Network.Fulcrum.TransactionProofReader(client: client)

        let failure = try await Self.captureNetworkError {
            try await request.fetch(using: reader)
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == request.expectedMessage)
        #expect(await request.didSkipDependentClientCall(on: client))
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

    enum ZeroHeightProofRequest: CaseIterable, CustomStringConvertible, Sendable {
        case merkleProof
        case positionResolution

        var description: String {
            switch self {
            case .merkleProof:
                "merkle proof"
            case .positionResolution:
                "position resolution"
            }
        }

        var expectedMessage: String {
            switch self {
            case .merkleProof:
                "Merkle proof requires a confirmed transaction height."
            case .positionResolution:
                "Transaction position resolution requires a positive block height."
            }
        }

        func makeClient() throws -> TransactionProofClientTestActor {
            switch self {
            case .merkleProof:
                return try TransactionProofClientTestActor(
                    heightResponse: NetworkFulcrumTransactionProofReaderValidator.makeHeightResponse(blockHeight: 0)
                )
            case .positionResolution:
                return try TransactionProofClientTestActor()
            }
        }

        func fetch(using reader: OpalBase.Network.Fulcrum.TransactionProofReader) async throws {
            switch self {
            case .merkleProof:
                _ = try await reader.fetchMerkleProof(
                    for: .init(naturalOrder: Data(repeating: 0x01, count: 32))
                )
            case .positionResolution:
                _ = try await reader.fetchTransactionIdentifier(
                    atHeight: 0,
                    position: 0,
                    shouldIncludeMerkleProof: false
                )
            }
        }

        func didSkipDependentClientCall(on client: TransactionProofClientTestActor) async -> Bool {
            switch self {
            case .merkleProof:
                return await client.readRequestedTransactionHash() == nil
            case .positionResolution:
                return await client.readRequestedPositionResolution() == nil
            }
        }
    }

    enum OversizedMerkleBranchRequest: CaseIterable, CustomStringConvertible, Sendable {
        case merkleProof
        case positionResolution

        var description: String {
            switch self {
            case .merkleProof:
                "merkle proof"
            case .positionResolution:
                "position resolution"
            }
        }

        func makeClient() throws -> TransactionProofClientTestActor {
            let oversizedBranch = Array(repeating: String(repeating: branchHashCharacter, count: 64), count: UInt.bitWidth)
            switch self {
            case .merkleProof:
                return try TransactionProofClientTestActor(
                    merkleResponse: NetworkFulcrumTransactionProofReaderValidator.makeMerkleResponse(
                        merkle: oversizedBranch,
                        position: 0
                    ),
                    heightResponse: NetworkFulcrumTransactionProofReaderValidator.makeHeightResponse(blockHeight: 12)
                )
            case .positionResolution:
                return try TransactionProofClientTestActor(
                    identifierResponse: NetworkFulcrumTransactionProofReaderValidator.makeIdentifierResponse(
                        merkle: oversizedBranch
                    )
                )
            }
        }

        func fetch(using reader: OpalBase.Network.Fulcrum.TransactionProofReader) async throws {
            switch self {
            case .merkleProof:
                _ = try await reader.fetchMerkleProof(
                    for: .init(naturalOrder: Data(repeating: 0x01, count: 32))
                )
            case .positionResolution:
                _ = try await reader.fetchTransactionIdentifier(
                    atHeight: 12,
                    position: 0,
                    shouldIncludeMerkleProof: true
                )
            }
        }

        private var branchHashCharacter: String {
            switch self {
            case .merkleProof:
                "a"
            case .positionResolution:
                "d"
            }
        }
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

    static func captureError(_ work: () throws -> Void) throws -> Swift.Error {
        do {
            try work()
            throw NetworkErrorCaptureFailure.didNotThrow
        } catch let failure as NetworkErrorCaptureFailure {
            throw failure
        } catch {
            return error
        }
    }
}
