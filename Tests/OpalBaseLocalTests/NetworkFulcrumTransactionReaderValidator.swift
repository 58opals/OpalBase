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

        let failure = await Self.captureNetworkError {
            _ = try await reader.fetchRawTransaction(for: malformedHash)
        }

        #expect(failure.reason == .decoding)
        #expect(failure.message == "Transaction payload has trailing bytes")
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

    @Test("falls back to raw transaction fetch when verbose decoding fails")
    func fetchDetailedTransactionFallsBackToRawAfterVerboseDecodingFailure() async throws {
        let fixture = try TransactionFixture.make()
        let client = TransactionReaderClientTestActor(
            rawTransactionHex: fixture.rawTransactionHexadecimal,
            verboseTransaction: fixture.verboseResponse,
            verboseError: SwiftFulcrum.Client.Error.coding(.decode(nil))
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

    @Test("falls back to raw transaction fetch when verbose block hash is malformed")
    func fetchDetailedTransactionFallsBackToRawAfterMalformedVerboseBlockHash() async throws {
        let fixture = try TransactionFixture.make()
        let verboseResponse = try TransactionFixture.makeVerboseResponse(
            transactionHash: fixture.transactionHash.reverseOrder.hexadecimalString,
            rawTransactionHexadecimal: fixture.rawTransactionHexadecimal,
            blockHashHexadecimal: "aa",
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

        let detail = try await reader.fetchDetailedTransaction(for: fixture.transactionHash)

        #expect(detail.rawTransactionData == fixture.rawTransactionData)
        #expect(detail.blockHash == nil)
        #expect(await client.readVerboseFetchCount() == 1)
        #expect(await client.readRawFetchCount() == 1)
    }

    @Test("falls back to raw transaction fetch when verbose size exceeds supported range")
    func fetchDetailedTransactionFallsBackToRawAfterOversizedVerboseSize() async throws {
        let fixture = try TransactionFixture.make()
        let verboseResponse = try TransactionFixture.makeVerboseResponse(
            transactionHash: fixture.transactionHash.reverseOrder.hexadecimalString,
            rawTransactionHexadecimal: fixture.rawTransactionHexadecimal,
            blockHashHexadecimal: fixture.blockHashData.hexadecimalString,
            blockTime: fixture.blockTime,
            confirmations: fixture.confirmations,
            transactionTime: fixture.transactionTime,
            size: Int(UInt32.max) + 1
        )
        let client = TransactionReaderClientTestActor(
            rawTransactionHex: fixture.rawTransactionHexadecimal,
            verboseTransaction: verboseResponse
        )
        let reader = OpalBase.Network.Fulcrum.TransactionReader(client: client)

        let detail = try await reader.fetchDetailedTransaction(for: fixture.transactionHash)

        #expect(detail.rawTransactionData == fixture.rawTransactionData)
        #expect(detail.size == UInt32(fixture.rawTransactionData.count))
        #expect(detail.blockHash == nil)
        #expect(await client.readVerboseFetchCount() == 1)
        #expect(await client.readRawFetchCount() == 1)
    }

    @Test("falls back to raw transaction fetch when verbose confirmations exceed supported range")
    func fetchDetailedTransactionFallsBackToRawAfterOversizedVerboseConfirmations() async throws {
        let fixture = try TransactionFixture.make()
        let verboseResponse = try TransactionFixture.makeVerboseResponseWithUnsignedMetadata(
            transactionHash: fixture.transactionHash.reverseOrder.hexadecimalString,
            rawTransactionHexadecimal: fixture.rawTransactionHexadecimal,
            blockHashHexadecimal: fixture.blockHashData.hexadecimalString,
            blockTime: UInt(fixture.blockTime),
            confirmations: UInt(UInt32.max) + 1,
            transactionTime: UInt(fixture.transactionTime),
            size: fixture.rawTransactionData.count
        )
        let client = TransactionReaderClientTestActor(
            rawTransactionHex: fixture.rawTransactionHexadecimal,
            verboseTransaction: verboseResponse
        )
        let reader = OpalBase.Network.Fulcrum.TransactionReader(client: client)

        let detail = try await reader.fetchDetailedTransaction(for: fixture.transactionHash)

        #expect(detail.rawTransactionData == fixture.rawTransactionData)
        #expect(detail.confirmations == nil)
        #expect(detail.blockHash == nil)
        #expect(await client.readVerboseFetchCount() == 1)
        #expect(await client.readRawFetchCount() == 1)
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

        let failure = await Self.captureNetworkError {
            _ = try await reader.fetchDetailedTransaction(for: fixture.transactionHash)
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == "Transaction payload hash mismatch")
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

        let failure = await Self.captureNetworkError {
            _ = try await reader.fetchDetailedTransaction(for: malformedHash)
        }

        #expect(failure.reason == .decoding)
        #expect(failure.message == "Transaction payload has trailing bytes")
        #expect(await client.readVerboseFetchCount() == 1)
        #expect(await client.readRawFetchCount() == 1)
    }

    @Test("does not retry raw transaction fetch for non-decoding failures")
    func fetchDetailedTransactionDoesNotRetryRawForNonDecodingFailures() async throws {
        let fixture = try TransactionFixture.make()
        let cases: [(String, Swift.Error, OpalBase.Network.Error)] = [
            (
                "timeout",
                SwiftFulcrum.Client.Error.client(.timeout(.seconds(3))),
                OpalBase.Network.Error(
                    reason: .timeout,
                    message: "Operation timed out",
                    metadata: ["timeoutSeconds": "3.0"]
                )
            ),
            (
                "transport",
                SwiftFulcrum.Client.Error.transport(.heartbeatTimeout),
                OpalBase.Network.Error(reason: .timeout, message: "Heartbeat timed out")
            ),
            (
                "server",
                OpalBase.Network.Error(reason: .server(code: -5), message: "missing transaction"),
                OpalBase.Network.Error(reason: .server(code: -5), message: "missing transaction")
            )
        ]

        for (_, verboseError, expected) in cases {
            let client = TransactionReaderClientTestActor(
                rawTransactionHex: fixture.rawTransactionHexadecimal,
                verboseTransaction: fixture.verboseResponse,
                verboseError: verboseError
            )
            let reader = OpalBase.Network.Fulcrum.TransactionReader(client: client)

            let failure = await Self.captureNetworkError {
                _ = try await reader.fetchDetailedTransaction(for: fixture.transactionHash)
            }

            #expect(failure == expected)
            #expect(await client.readVerboseFetchCount() == 1)
            #expect(await client.readRawFetchCount() == 0)
        }
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

private actor TransactionReaderClientTestActor: OpalBase.Network.Fulcrum.TransactionReaderClient {
    private let rawTransactionHex: String
    private let verboseTransaction: SwiftFulcrum.Response.Blockchain.Transaction.Get
    private let rawError: Swift.Error?
    private let verboseError: Swift.Error?
    private var rawRequests: [String] = []
    private var verboseRequests: [String] = []

    init(
        rawTransactionHex: String,
        verboseTransaction: SwiftFulcrum.Response.Blockchain.Transaction.Get,
        rawError: Swift.Error? = nil,
        verboseError: Swift.Error? = nil
    ) {
        self.rawTransactionHex = rawTransactionHex
        self.verboseTransaction = verboseTransaction
        self.rawError = rawError
        self.verboseError = verboseError
    }

    func fetchRawTransaction(
        transactionHash: String,
        options _: SwiftFulcrum.Client.Call.Options
    ) async throws -> String {
        rawRequests.append(transactionHash)
        if let rawError {
            throw rawError
        }
        return rawTransactionHex
    }

    func fetchVerboseTransaction(
        transactionHash: String,
        options _: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Blockchain.Transaction.Get {
        verboseRequests.append(transactionHash)
        if let verboseError {
            throw verboseError
        }
        return verboseTransaction
    }

    func readRawFetchCount() -> Int {
        rawRequests.count
    }

    func readVerboseFetchCount() -> Int {
        verboseRequests.count
    }

    func readLastRawTransactionHash() -> String? {
        rawRequests.last
    }

    func readLastVerboseTransactionHash() -> String? {
        verboseRequests.last
    }
}

private struct TransactionFixture {
    let transactionHash: OpalBase.Transaction.Hash
    let rawTransactionData: Data
    let rawTransactionHexadecimal: String
    let verboseResponse: SwiftFulcrum.Response.Blockchain.Transaction.Get
    let blockHashData: Data
    let blockTime: UInt32
    let confirmations: UInt32
    let transactionTime: UInt32

    static func make() throws -> TransactionFixture {
        let transaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: .init(naturalOrder: Data(repeating: 0x01, count: 32)),
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data()
                )
            ],
            outputs: [
                .init(value: 546, lockingScript: Data([0x51]))
            ],
            lockTime: 0
        )
        let rawTransactionData = try transaction.encode()
        let transactionHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(rawTransactionData)
        )
        let rawTransactionHexadecimal = rawTransactionData.hexadecimalString
        let blockHashData = Data(repeating: 0xaa, count: 32)
        let blockHashHexadecimal = blockHashData.hexadecimalString
        let blockTime: UInt32 = 1_710_000_000
        let confirmations: UInt32 = 12
        let transactionTime: UInt32 = 1_710_000_100
        let verboseResponse = try makeVerboseResponse(
            transactionHash: transactionHash.reverseOrder.hexadecimalString,
            rawTransactionHexadecimal: rawTransactionHexadecimal,
            blockHashHexadecimal: blockHashHexadecimal,
            blockTime: blockTime,
            confirmations: confirmations,
            transactionTime: transactionTime,
            size: rawTransactionData.count
        )

        return TransactionFixture(
            transactionHash: transactionHash,
            rawTransactionData: rawTransactionData,
            rawTransactionHexadecimal: rawTransactionHexadecimal,
            verboseResponse: verboseResponse,
            blockHashData: blockHashData,
            blockTime: blockTime,
            confirmations: confirmations,
            transactionTime: transactionTime
        )
    }

    static func makeVerboseResponse(
        transactionHash: String,
        rawTransactionHexadecimal: String,
        blockHashHexadecimal: String,
        blockTime: UInt32?,
        confirmations: UInt32?,
        transactionTime: UInt32?,
        size: Int
    ) throws -> SwiftFulcrum.Response.Blockchain.Transaction.Get {
        try makeVerboseResponseWithUnsignedMetadata(
            transactionHash: transactionHash,
            rawTransactionHexadecimal: rawTransactionHexadecimal,
            blockHashHexadecimal: blockHashHexadecimal,
            blockTime: blockTime.map(UInt.init),
            confirmations: confirmations.map(UInt.init),
            transactionTime: transactionTime.map(UInt.init),
            size: size
        )
    }

    static func makeVerboseResponseWithUnsignedMetadata(
        transactionHash: String,
        rawTransactionHexadecimal: String,
        blockHashHexadecimal: String,
        blockTime: UInt?,
        confirmations: UInt?,
        transactionTime: UInt?,
        size: Int
    ) throws -> SwiftFulcrum.Response.Blockchain.Transaction.Get {
        var payload: [String: Any] = [
            "blockhash": blockHashHexadecimal,
            "hash": transactionHash,
            "hex": rawTransactionHexadecimal,
            "locktime": 0,
            "size": size,
            "txid": transactionHash,
            "version": 2,
            "vin": [
                [
                    "scriptSig": [
                        "asm": "",
                        "hex": ""
                    ],
                    "sequence": UInt32.max,
                    "txid": String(repeating: "1", count: 64),
                    "vout": 0
                ]
            ],
            "vout": [
                [
                    "n": 0,
                    "scriptPubKey": [
                        "addresses": ["bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"],
                        "asm": "1",
                        "hex": "51",
                        "reqSigs": 1,
                        "type": "pubkeyhash"
                    ],
                    "value": 0.00000546
                ]
            ]
        ]
        if let blockTime {
            payload["blocktime"] = blockTime
        }
        if let confirmations {
            payload["confirmations"] = confirmations
        }
        if let transactionTime {
            payload["time"] = transactionTime
        }
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(
            SwiftFulcrum.Response.Blockchain.Transaction.Get.self,
            from: payloadData
        )
    }
}

private extension NetworkFulcrumTransactionReaderValidator {
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
