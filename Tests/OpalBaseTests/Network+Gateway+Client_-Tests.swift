import Foundation
import Testing
@testable import OpalBase

@Suite("Network.Gateway.Client")
struct NetworkGatewayClientTests {
    @Test("Broadcast caches acknowledged transactions", .timeLimit(.minutes(1)))
    func broadcastCachesKnownTransactions() async throws {
        let acknowledgedHash = Transaction.Hash(naturalOrder: Data(repeating: 0xAB, count: 32))
        let transaction = Transaction.fixture()

        let client = MockGatewayClient(
            currentMempool: [],
            broadcast: { [transaction] submitted in
                #expect(submitted.encode() == transaction.encode())
                return acknowledgedHash
            }
        )

        let gateway = Network.Gateway(client: client, configuration: .testingOnline())
        let returnedHash = try await gateway.broadcast(transaction)

        #expect(returnedHash == acknowledgedHash)
        #expect(client.broadcastCallCount == 1)

        let isKnown = await gateway.isInMempool(acknowledgedHash)
        #expect(isKnown)
    }

    @Test("Broadcast resolves already known errors", .timeLimit(.minutes(1)))
    func broadcastResolvesAlreadyKnownTransactions() async throws {
        enum BroadcastFailure: Swift.Error { case rejected }

        let acknowledgedHash = Transaction.Hash(naturalOrder: Data(repeating: 0xCD, count: 32))
        let transaction = Transaction.fixture()

        let expectedSubmissionHash = Transaction.Hash(naturalOrder: HASH256.hash(transaction.encode()))

        let client = MockGatewayClient(
            currentMempool: [],
            broadcast: { _ in throw BroadcastFailure.rejected },
            interpretBroadcastError: { error, expected in
                #expect(error is BroadcastFailure)
                #expect(expected == expectedSubmissionHash)
                return .alreadyKnown(acknowledgedHash)
            }
        )

        let gateway = Network.Gateway(client: client, configuration: .testingOnline())
        let returnedHash = try await gateway.broadcast(transaction)

        #expect(returnedHash == acknowledgedHash)
        #expect(client.broadcastCallCount == 1)

        let isKnown = await gateway.isInMempool(acknowledgedHash)
        #expect(isKnown)
    }

    @Test("Transport errors are normalized", .timeLimit(.minutes(1)))
    func fetchOperationsSurfaceNormalizedErrors() async throws {
        enum TransportFailure: Swift.Error { case offline }

        let expectedHash = Transaction.Hash(naturalOrder: Data(repeating: 0xEF, count: 32))
        let normalized = Network.Gateway.Error(
            reason: .transport(description: "Disconnected"),
            retry: .after(1)
        )

        let client = MockGatewayClient(
            currentMempool: [], broadcast: {_ in return .init(dataFromRPC: .init())},
            fetch: { _ in throw TransportFailure.offline },
            normalize: { error, request in
                #expect(error is TransportFailure)
                #expect(request == .transaction(expectedHash))
                return normalized
            }
        )

        let gateway = Network.Gateway(client: client, configuration: .testingOnline())
        let thrown = await #expect(throws: Network.Gateway.Error.self) {
            try await gateway.getTransaction(for: expectedHash)
        }

        #expect(thrown == normalized)
    }
}

private extension Transaction {
    /// Provides a deterministic single-input, single-output fixture for testing.
    static func fixture() -> Transaction {
        let previousHash = Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32))
        let input = Transaction.Input(
            previousTransactionHash: previousHash,
            previousTransactionOutputIndex: 0,
            unlockingScript: Data([0x51])
        )
        let output = Transaction.Output(value: 546, lockingScript: Data([0x51]))
        return Transaction(version: 2, inputs: [input], outputs: [output], lockTime: 0)
    }
}

private final class MockGatewayClient: Network.Gateway.Client, @unchecked Sendable {
    enum MockError: Swift.Error {
        case unimplemented(String)
    }

    private let lock = NSLock()

    private var _currentMempool: Set<Transaction.Hash>
    private var broadcastInvocations = 0

    private let broadcastClosure: @Sendable (Transaction) async throws -> Transaction.Hash
    private let fetchClosure: @Sendable (Transaction.Hash) async throws -> Transaction?
    private let rawClosure: @Sendable (Transaction.Hash) async throws -> Data
    private let detailedClosure: @Sendable (Transaction.Hash) async throws -> Transaction.Detailed
    private let estimateFeeClosure: @Sendable (Int) async throws -> Satoshi
    private let relayFeeClosure: @Sendable () async throws -> Satoshi
    private let headerClosure: @Sendable (UInt32) async throws -> Network.Gateway.HeaderPayload?
    private let pingClosure: @Sendable () async throws -> Void
    private let interpretClosure: @Sendable (Swift.Error, Transaction.Hash) -> Network.Gateway.BroadcastResolution?
    private let normalizeClosure: @Sendable (Swift.Error, Network.Gateway.Request) -> Network.Gateway.Error?

    init(
        currentMempool: Set<Transaction.Hash>,
        broadcast: @escaping @Sendable (Transaction) async throws -> Transaction.Hash,
        fetch: @escaping @Sendable (Transaction.Hash) async throws -> Transaction? = { _ in nil },
        getRaw: @escaping @Sendable (Transaction.Hash) async throws -> Data = { _ in throw MockError.unimplemented("getRawTransaction") },
        detailed: @escaping @Sendable (Transaction.Hash) async throws -> Transaction.Detailed = { _ in throw MockError.unimplemented("getDetailedTransaction") },
        estimateFee: @escaping @Sendable (Int) async throws -> Satoshi = { _ in Satoshi() },
        relayFee: @escaping @Sendable () async throws -> Satoshi = { Satoshi() },
        header: @escaping @Sendable (UInt32) async throws -> Network.Gateway.HeaderPayload? = { _ in nil },
        ping: @escaping @Sendable () async throws -> Void = {},
        interpretBroadcastError: @escaping @Sendable (Swift.Error, Transaction.Hash) -> Network.Gateway.BroadcastResolution? = { _, _ in nil },
        normalize: @escaping @Sendable (Swift.Error, Network.Gateway.Request) -> Network.Gateway.Error? = { _, _ in nil }
    ) {
        self._currentMempool = currentMempool
        self.broadcastClosure = broadcast
        self.fetchClosure = fetch
        self.rawClosure = getRaw
        self.detailedClosure = detailed
        self.estimateFeeClosure = estimateFee
        self.relayFeeClosure = relayFee
        self.headerClosure = header
        self.pingClosure = ping
        self.interpretClosure = interpretBroadcastError
        self.normalizeClosure = normalize
    }

    var currentMempool: Set<Transaction.Hash> {
        get { lock.withLock { _currentMempool } }
        set { lock.withLock { _currentMempool = newValue } }
    }

    var broadcastCallCount: Int { lock.withLock { broadcastInvocations } }

    func broadcast(_ transaction: Transaction) async throws -> Transaction.Hash {
        let hash = try await broadcastClosure(transaction)
        lock.withLock { broadcastInvocations += 1 }
        return hash
    }

    func fetch(_ hash: Transaction.Hash) async throws -> Transaction? {
        try await fetchClosure(hash)
    }

    func getRawTransaction(for hash: Transaction.Hash) async throws -> Data {
        try await rawClosure(hash)
    }

    func getDetailedTransaction(for hash: Transaction.Hash) async throws -> Transaction.Detailed {
        try await detailedClosure(hash)
    }

    func getEstimateFee(targetBlocks: Int) async throws -> Satoshi {
        try await estimateFeeClosure(targetBlocks)
    }

    func getRelayFee() async throws -> Satoshi {
        try await relayFeeClosure()
    }

    func getHeader(height: UInt32) async throws -> Network.Gateway.HeaderPayload? {
        try await headerClosure(height)
    }

    func pingHeadersTip() async throws {
        try await pingClosure()
    }

    nonisolated func interpretBroadcastError(_ error: Swift.Error, expectedHash: Transaction.Hash) -> Network.Gateway.BroadcastResolution? {
        interpretClosure(error, expectedHash)
    }

    nonisolated func normalize(error: Swift.Error, during request: Network.Gateway.Request) -> Network.Gateway.Error? {
        normalizeClosure(error, request)
    }
}

private extension Network.Gateway.Configuration {
    /// Provides a network configuration suitable for deterministic testing.
    static func testingOnline(
        mempoolTTL: TimeInterval = 30,
        seenTTL: TimeInterval = 600,
        headerFreshness: TimeInterval = 0,
        healthRetryDelay: TimeInterval = 0.1
    ) -> Network.Gateway.Configuration {
        .init(
            mempoolTTL: mempoolTTL,
            seenTTL: seenTTL,
            headerFreshness: headerFreshness,
            healthRetryDelay: healthRetryDelay,
            initialStatus: .online,
            initialHeaderUpdate: Date(),
            router: .init(),
            instrumentation: .init()
        )
    }
}
