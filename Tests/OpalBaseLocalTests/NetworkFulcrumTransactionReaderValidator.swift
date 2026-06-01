// NetworkFulcrumTransactionReaderValidator.swift

import Foundation
import Testing
import SwiftFulcrum
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.Fulcrum.TransactionReader", .tags(.unit, .network))
struct NetworkFulcrumTransactionReaderValidator {
    @Test("fetches raw transactions from raw hex responses without caching raw-only reads")
    func fetchRawTransactionReturnsDecodedBytes() async throws {
        let fixture = try TransactionFixture.make()
        let client = TransactionReaderClientTestActor(
            rawTransactionHex: fixture.rawTransactionHexadecimal,
            verboseTransaction: fixture.verboseResponse
        )
        let reader = OpalBase.Network.Fulcrum.TransactionReader(client: client)

        let first = try await reader.fetchRawTransaction(for: fixture.transactionHash)
        let second = try await reader.fetchRawTransaction(for: fixture.transactionHash)

        #expect(first == fixture.rawTransactionData)
        #expect(second == fixture.rawTransactionData)
        #expect(await client.readRawFetchCount() == 2)
        #expect(await client.readVerboseFetchCount() == 0)
        #expect(await client.readLastRawTransactionHash() == fixture.transactionHash.reverseOrder.hexadecimalString)
    }

    @Test("fetchRawTransaction rejects trailing bytes after decoded transaction")
    func fetchRawTransactionRejectsTrailingPayloadBytes() async throws {
        let fixture = try TransactionFixture.make()
        let malformedRawTransactionData = fixture.rawTransactionData + Data([0x00])
        let malformedHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(malformedRawTransactionData)
        )
        let client = TransactionReaderClientTestActor(
            rawTransactionHex: malformedRawTransactionData.hexadecimalString,
            verboseTransaction: fixture.verboseResponse
        )
        let reader = OpalBase.Network.Fulcrum.TransactionReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchRawTransaction(for: malformedHash)
        }

        #expect(failure.reason == .decoding)
        #expect(failure.message == "Transaction payload has trailing bytes")
        #expect(await client.readRawFetchCount() == 1)
        #expect(await client.readVerboseFetchCount() == 0)
    }

    @Test("fetchRawTransaction rejects prefixed raw transaction hex")
    func fetchRawTransactionRejectsPrefixedRawTransactionHex() async throws {
        let fixture = try TransactionFixture.make()
        let client = TransactionReaderClientTestActor(
            rawTransactionHex: "0x" + fixture.rawTransactionHexadecimal,
            verboseTransaction: fixture.verboseResponse
        )
        let reader = OpalBase.Network.Fulcrum.TransactionReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchRawTransaction(for: fixture.transactionHash)
        }

        #expect(failure.reason == .decoding)
        #expect(failure.message == "Cannot decode raw transaction hex")
        #expect(await client.readRawFetchCount() == 1)
        #expect(await client.readVerboseFetchCount() == 0)
    }

    @Test("fetches detailed transactions from verbose responses")
    func fetchDetailedTransactionMapsVerboseResponses() async throws {
        let fixture = try TransactionFixture.make()
        let client = TransactionReaderClientTestActor(
            rawTransactionHex: fixture.rawTransactionHexadecimal,
            verboseTransaction: fixture.verboseResponse
        )
        let reader = OpalBase.Network.Fulcrum.TransactionReader(client: client)

        let detail = try await reader.fetchDetailedTransaction(for: fixture.transactionHash)

        #expect(detail.hash == fixture.transactionHash)
        #expect(detail.rawTransactionData == fixture.rawTransactionData)
        #expect(detail.blockHash == fixture.blockHashData)
        #expect(detail.blockTime == fixture.blockTime)
        #expect(detail.confirmations == fixture.confirmations)
        #expect(detail.size == UInt32(fixture.rawTransactionData.count))
        #expect(detail.time == fixture.transactionTime)
        #expect(try detail.transaction.encode() == fixture.rawTransactionData)
        #expect(await client.readVerboseFetchCount() == 1)
        #expect(await client.readRawFetchCount() == 0)
        #expect(await client.readLastVerboseTransactionHash() == fixture.transactionHash.reverseOrder.hexadecimalString)
    }

    @Test("transaction details normalize sliced payload data")
    func transactionDetailsNormalizeSlicedPayloadData() throws {
        let fixture = try TransactionFixture.make()
        let rawTransactionData = Self.makeSlicedData(from: fixture.rawTransactionData)
        let blockHash = Self.makeSlicedData(from: fixture.blockHashData)
        let transaction = try OpalBase.Transaction.decode(
            from: fixture.rawTransactionData
        ).transaction

        let detail = OpalBase.Transaction.Detail(
            transaction: transaction,
            blockHash: blockHash,
            blockTime: fixture.blockTime,
            confirmations: fixture.confirmations,
            hash: fixture.transactionHash,
            rawTransactionData: rawTransactionData,
            size: UInt32(fixture.rawTransactionData.count),
            time: fixture.transactionTime
        )

        #expect(rawTransactionData.startIndex != 0)
        #expect(blockHash.startIndex != 0)
        #expect(detail.rawTransactionData == fixture.rawTransactionData)
        #expect(detail.blockHash == fixture.blockHashData)
        #expect(detail.rawTransactionData.startIndex == 0)
        #expect(detail.blockHash?.startIndex == 0)
    }

    @Test("preserves missing verbose transaction metadata as nil")
    func fetchDetailedTransactionPreservesMissingVerboseMetadata() async throws {
        let fixture = try TransactionFixture.make()
        let verboseResponse = try TransactionFixture.makeVerboseResponse(
            transactionHash: fixture.transactionHash.reverseOrder.hexadecimalString,
            rawTransactionHexadecimal: fixture.rawTransactionHexadecimal,
            blockHashHexadecimal: fixture.blockHashData.hexadecimalString,
            blockTime: nil,
            confirmations: nil,
            transactionTime: nil,
            size: fixture.rawTransactionData.count
        )
        let client = TransactionReaderClientTestActor(
            rawTransactionHex: fixture.rawTransactionHexadecimal,
            verboseTransaction: verboseResponse
        )
        let reader = OpalBase.Network.Fulcrum.TransactionReader(client: client)

        let detail = try await reader.fetchDetailedTransaction(for: fixture.transactionHash)

        #expect(detail.hash == fixture.transactionHash)
        #expect(detail.rawTransactionData == fixture.rawTransactionData)
        #expect(detail.blockHash == fixture.blockHashData)
        #expect(detail.blockTime == nil)
        #expect(detail.confirmations == nil)
        #expect(detail.time == nil)
        #expect(try detail.transaction.encode() == fixture.rawTransactionData)
        #expect(await client.readVerboseFetchCount() == 1)
        #expect(await client.readRawFetchCount() == 0)
    }

    @Test(
        "falls back to raw transaction fetch after verbose decode failures",
        arguments: VerboseDecodingFallbackCase.allCases
    )
    func fetchDetailedTransactionFallsBackToRawAfterVerboseDecodeFailures(
        _ fallbackCase: VerboseDecodingFallbackCase
    ) async throws {
        let fixture = try TransactionFixture.make()
        let client = TransactionReaderClientTestActor(
            rawTransactionHex: fixture.rawTransactionHexadecimal,
            verboseTransaction: fixture.verboseResponse,
            verboseError: fallbackCase.verboseError
        )
        let reader = OpalBase.Network.Fulcrum.TransactionReader(client: client)

        let detail = try await reader.fetchDetailedTransaction(for: fixture.transactionHash)

        #expect(detail.hash == fixture.transactionHash)
        #expect(detail.rawTransactionData == fixture.rawTransactionData)
        #expect(detail.blockHash == nil)
        #expect(detail.blockTime == nil)
        #expect(detail.confirmations == nil)
        #expect(detail.time == nil)
        #expect(try detail.transaction.encode() == fixture.rawTransactionData)
        #expect(await client.readVerboseFetchCount() == 1)
        #expect(await client.readRawFetchCount() == 1)
    }

    @Test(
        "falls back to raw transaction fetch after invalid verbose metadata",
        arguments: VerboseMetadataFallbackCase.allCases
    )
    func fetchDetailedTransactionFallsBackToRawAfterInvalidVerboseMetadata(
        _ fallbackCase: VerboseMetadataFallbackCase
    ) async throws {
        let fixture = try TransactionFixture.make()
        let verboseResponse = try fallbackCase.makeVerboseResponse(for: fixture)
        let client = TransactionReaderClientTestActor(
            rawTransactionHex: fixture.rawTransactionHexadecimal,
            verboseTransaction: verboseResponse
        )
        let reader = OpalBase.Network.Fulcrum.TransactionReader(client: client)

        let detail = try await reader.fetchDetailedTransaction(for: fixture.transactionHash)

        #expect(detail.hash == fixture.transactionHash)
        #expect(detail.rawTransactionData == fixture.rawTransactionData)
        #expect(detail.size == UInt32(fixture.rawTransactionData.count))
        #expect(detail.blockHash == nil)
        #expect(detail.blockTime == nil)
        #expect(detail.confirmations == nil)
        #expect(detail.time == nil)
        #expect(try detail.transaction.encode() == fixture.rawTransactionData)
        #expect(await client.readVerboseFetchCount() == 1)
        #expect(await client.readRawFetchCount() == 1)
    }

    @Test("preserves zero verbose confirmations without a block hash")
    func fetchDetailedTransactionPreservesUnconfirmedVerboseResponseWithoutBlockHash() async throws {
        let fixture = try TransactionFixture.make()
        let verboseResponse = try TransactionFixture.makeVerboseResponse(
            transactionHash: fixture.transactionHash.reverseOrder.hexadecimalString,
            rawTransactionHexadecimal: fixture.rawTransactionHexadecimal,
            blockHashHexadecimal: nil,
            blockTime: nil,
            confirmations: 0,
            transactionTime: nil,
            size: fixture.rawTransactionData.count
        )
        let client = TransactionReaderClientTestActor(
            rawTransactionHex: fixture.rawTransactionHexadecimal,
            verboseTransaction: verboseResponse
        )
        let reader = OpalBase.Network.Fulcrum.TransactionReader(client: client)

        let detail = try await reader.fetchDetailedTransaction(for: fixture.transactionHash)

        #expect(detail.hash == fixture.transactionHash)
        #expect(detail.blockHash == nil)
        #expect(detail.confirmations == 0)
        #expect(await client.readVerboseFetchCount() == 1)
        #expect(await client.readRawFetchCount() == 0)
    }

    @Test("fetchDetailedTransaction rejects transaction payload hash mismatches")
    func fetchDetailedTransactionRejectsPayloadHashMismatches() async throws {
        let fixture = try TransactionFixture.make()
        var mismatchedRawTransactionData = fixture.rawTransactionData
        mismatchedRawTransactionData[mismatchedRawTransactionData.count - 1] ^= 0x01
        let verboseResponse = try TransactionFixture.makeVerboseResponse(
            transactionHash: fixture.transactionHash.reverseOrder.hexadecimalString,
            rawTransactionHexadecimal: mismatchedRawTransactionData.hexadecimalString,
            blockHashHexadecimal: fixture.blockHashData.hexadecimalString,
            blockTime: fixture.blockTime,
            confirmations: fixture.confirmations,
            transactionTime: fixture.transactionTime,
            size: mismatchedRawTransactionData.count
        )
        let client = TransactionReaderClientTestActor(
            rawTransactionHex: mismatchedRawTransactionData.hexadecimalString,
            verboseTransaction: verboseResponse
        )
        let reader = OpalBase.Network.Fulcrum.TransactionReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchDetailedTransaction(for: fixture.transactionHash)
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == "Transaction payload hash mismatch")
        #expect(await client.readVerboseFetchCount() == 1)
        #expect(await client.readRawFetchCount() == 0)
    }

    @Test("fetchDetailedTransaction rejects verbose transaction identifier mismatches")
    func fetchDetailedTransactionRejectsVerboseIdentifierMismatches() async throws {
        let fixture = try TransactionFixture.make()
        let mismatchedTransactionIdentifier = String(repeating: "0", count: 64)
        let verboseResponse = try TransactionFixture.makeVerboseResponse(
            transactionHash: mismatchedTransactionIdentifier,
            rawTransactionHexadecimal: fixture.rawTransactionHexadecimal,
            blockHashHexadecimal: fixture.blockHashData.hexadecimalString,
            blockTime: fixture.blockTime,
            confirmations: fixture.confirmations,
            transactionTime: fixture.transactionTime,
            size: fixture.rawTransactionData.count
        )
        let client = TransactionReaderClientTestActor(
            rawTransactionHex: fixture.rawTransactionHexadecimal,
            verboseTransaction: verboseResponse
        )
        let reader = OpalBase.Network.Fulcrum.TransactionReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchDetailedTransaction(for: fixture.transactionHash)
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == "Verbose transaction identifier mismatch")
        #expect(await client.readVerboseFetchCount() == 1)
        #expect(await client.readRawFetchCount() == 0)
    }

    @Test("fetchDetailedTransaction rejects trailing bytes after decoded transaction")
    func fetchDetailedTransactionRejectsTrailingPayloadBytes() async throws {
        let fixture = try TransactionFixture.make()
        let malformedRawTransactionData = fixture.rawTransactionData + Data([0x00])
        let malformedHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(malformedRawTransactionData)
        )
        let verboseResponse = try TransactionFixture.makeVerboseResponse(
            transactionHash: malformedHash.reverseOrder.hexadecimalString,
            rawTransactionHexadecimal: malformedRawTransactionData.hexadecimalString,
            blockHashHexadecimal: fixture.blockHashData.hexadecimalString,
            blockTime: fixture.blockTime,
            confirmations: fixture.confirmations,
            transactionTime: fixture.transactionTime,
            size: malformedRawTransactionData.count
        )
        let client = TransactionReaderClientTestActor(
            rawTransactionHex: malformedRawTransactionData.hexadecimalString,
            verboseTransaction: verboseResponse
        )
        let reader = OpalBase.Network.Fulcrum.TransactionReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchDetailedTransaction(for: malformedHash)
        }

        #expect(failure.reason == .decoding)
        #expect(failure.message == "Transaction payload has trailing bytes")
        #expect(await client.readVerboseFetchCount() == 1)
        #expect(await client.readRawFetchCount() == 1)
    }

    @Test(
        "does not retry raw transaction fetch for non-decoding failures",
        arguments: NonDecodingFailureCase.allCases
    )
    func fetchDetailedTransactionDoesNotRetryRawForNonDecodingFailures(_ failureCase: NonDecodingFailureCase) async throws {
        let fixture = try TransactionFixture.make()

        let client = TransactionReaderClientTestActor(
            rawTransactionHex: fixture.rawTransactionHexadecimal,
            verboseTransaction: fixture.verboseResponse,
            verboseError: failureCase.verboseError
        )
        let reader = OpalBase.Network.Fulcrum.TransactionReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchDetailedTransaction(for: fixture.transactionHash)
        }

        #expect(failure == failureCase.expected)
        #expect(await client.readVerboseFetchCount() == 1)
        #expect(await client.readRawFetchCount() == 0)
    }

    @Test("reuses cached detailed transactions for repeated detailed and raw reads")
    func detailedTransactionCacheServesRepeatedRequests() async throws {
        let fixture = try TransactionFixture.make()
        let client = TransactionReaderClientTestActor(
            rawTransactionHex: fixture.rawTransactionHexadecimal,
            verboseTransaction: fixture.verboseResponse
        )
        let cache = OpalBase.Transaction.Cache()
        let reader = OpalBase.Network.Fulcrum.TransactionReader(client: client, cache: cache)

        let first = try await reader.fetchDetailedTransaction(for: fixture.transactionHash)
        let second = try await reader.fetchDetailedTransaction(for: fixture.transactionHash)
        let cachedRaw = try await reader.fetchRawTransaction(for: fixture.transactionHash)

        #expect(first.hash == second.hash)
        #expect(first.rawTransactionData == second.rawTransactionData)
        #expect(first.blockHash == second.blockHash)
        #expect(cachedRaw == fixture.rawTransactionData)
        #expect(await client.readVerboseFetchCount() == 1)
        #expect(await client.readRawFetchCount() == 0)
    }
}

extension NetworkFulcrumTransactionReaderValidator {
    enum VerboseDecodingFallbackCase: CaseIterable, CustomStringConvertible, Sendable {
        case genericDecode
        case malformedBlockHash
        case prefixedBlockHash

        var description: String {
            switch self {
            case .genericDecode:
                "generic decode"
            case .malformedBlockHash:
                "malformed block hash"
            case .prefixedBlockHash:
                "prefixed block hash"
            }
        }

        var verboseError: Swift.Error {
            switch self {
            case .genericDecode:
                return SwiftFulcrum.Client.Error.coding(.decode(nil))
            case .malformedBlockHash, .prefixedBlockHash:
                return NetworkFulcrumTransactionReaderValidator.makeDecodeError(
                    "Expected block hash to be exactly 64 hex characters"
                )
            }
        }
    }

    enum VerboseMetadataFallbackCase: CaseIterable, CustomStringConvertible, Sendable {
        case oversizedSize
        case mismatchedSize
        case oversizedConfirmations
        case confirmedWithoutBlockHash

        var description: String {
            switch self {
            case .oversizedSize:
                "oversized size"
            case .mismatchedSize:
                "mismatched size"
            case .oversizedConfirmations:
                "oversized confirmations"
            case .confirmedWithoutBlockHash:
                "confirmed without block hash"
            }
        }

        func makeVerboseResponse(
            for fixture: TransactionFixture
        ) throws -> SwiftFulcrum.Response.Blockchain.Transaction.Verbose {
            switch self {
            case .oversizedSize:
                return try TransactionFixture.makeVerboseResponse(
                    transactionHash: fixture.transactionHash.reverseOrder.hexadecimalString,
                    rawTransactionHexadecimal: fixture.rawTransactionHexadecimal,
                    blockHashHexadecimal: fixture.blockHashData.hexadecimalString,
                    blockTime: fixture.blockTime,
                    confirmations: fixture.confirmations,
                    transactionTime: fixture.transactionTime,
                    size: Int(UInt32.max) + 1
                )
            case .mismatchedSize:
                return try TransactionFixture.makeVerboseResponse(
                    transactionHash: fixture.transactionHash.reverseOrder.hexadecimalString,
                    rawTransactionHexadecimal: fixture.rawTransactionHexadecimal,
                    blockHashHexadecimal: fixture.blockHashData.hexadecimalString,
                    blockTime: fixture.blockTime,
                    confirmations: fixture.confirmations,
                    transactionTime: fixture.transactionTime,
                    size: fixture.rawTransactionData.count + 1
                )
            case .oversizedConfirmations:
                return try TransactionFixture.makeVerboseResponseWithUnsignedMetadata(
                    transactionHash: fixture.transactionHash.reverseOrder.hexadecimalString,
                    rawTransactionHexadecimal: fixture.rawTransactionHexadecimal,
                    blockHashHexadecimal: fixture.blockHashData.hexadecimalString,
                    blockTime: UInt(fixture.blockTime),
                    confirmations: UInt(UInt32.max) + 1,
                    transactionTime: UInt(fixture.transactionTime),
                    size: fixture.rawTransactionData.count
                )
            case .confirmedWithoutBlockHash:
                return try TransactionFixture.makeVerboseResponse(
                    transactionHash: fixture.transactionHash.reverseOrder.hexadecimalString,
                    rawTransactionHexadecimal: fixture.rawTransactionHexadecimal,
                    blockHashHexadecimal: nil,
                    blockTime: fixture.blockTime,
                    confirmations: fixture.confirmations,
                    transactionTime: fixture.transactionTime,
                    size: fixture.rawTransactionData.count
                )
            }
        }
    }

    enum NonDecodingFailureCase: CaseIterable, Sendable {
        case timeout
        case transport
        case server

        var verboseError: Swift.Error {
            switch self {
            case .timeout:
                return SwiftFulcrum.Client.Error.client(.timeout(.seconds(3)))
            case .transport:
                return SwiftFulcrum.Client.Error.transport(.heartbeatTimeout)
            case .server:
                return OpalBase.Network.Error(reason: .server(code: -5), message: "missing transaction")
            }
        }

        var expected: OpalBase.Network.Error {
            switch self {
            case .timeout:
                return OpalBase.Network.Error(
                    reason: .timeout,
                    message: "Operation timed out",
                    metadata: ["timeoutSeconds": "3.0"]
                )
            case .transport:
                return OpalBase.Network.Error(reason: .timeout, message: "Heartbeat timed out")
            case .server:
                return OpalBase.Network.Error(reason: .server(code: -5), message: "missing transaction")
            }
        }
    }

    struct DecodeFailure: Swift.Error, CustomStringConvertible {
        let description: String
    }

    enum NetworkErrorCaptureFailure: Swift.Error {
        case didNotThrow
        case unexpected(Swift.Error)
    }

    static func makeDecodeError(_ message: String) -> SwiftFulcrum.Client.Error {
        .coding(.decode(DecodeFailure(description: ".unexpectedFormat(\"\(message)\")")))
    }

    static func makeSlicedData(from data: Data) -> Data {
        var paddedData = Data([0x00])
        paddedData.append(data)
        return paddedData[paddedData.index(after: paddedData.startIndex)...]
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
