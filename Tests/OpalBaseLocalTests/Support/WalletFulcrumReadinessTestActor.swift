import Foundation
@testable import OpalBase

enum WalletFulcrumReadinessTestFailure: Swift.Error, Sendable {
    case forced(String)
    case timedOut(String)
}

/// A single network response held until the test supplies its result.
struct WalletFulcrumReadinessQueryGate<Value: Sendable>: Sendable {
    private let stream: AsyncThrowingStream<Value, Swift.Error>
    private let continuation: AsyncThrowingStream<Value, Swift.Error>.Continuation

    init() {
        let pair = AsyncThrowingStream<Value, Swift.Error>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    func value() async throws -> Value {
        var iterator = stream.makeAsyncIterator()
        guard let value = try await iterator.next() else { throw CancellationError() }
        return value
    }

    func succeed(_ value: Value) {
        continuation.yield(value)
        continuation.finish()
    }

    func fail(_ message: String) {
        continuation.finish(throwing: WalletFulcrumReadinessTestFailure.forced(message))
    }
}

actor WalletFulcrumReadinessProbe<Value: Sendable> {
    private var values: [Value] = []
    private var continuations: [UUID: AsyncStream<[Value]>.Continuation] = [:]

    func append(_ value: Value) {
        values.append(value)
        for continuation in continuations.values { continuation.yield(values) }
    }

    func snapshot() -> [Value] { values }

    func wait(_ description: String, matching predicate: @escaping @Sendable ([Value]) -> Bool) async throws -> [Value] {
        let identifier = UUID()
        let pair = AsyncStream<[Value]>.makeStream()
        continuations[identifier] = pair.continuation
        pair.continuation.yield(values)
        defer {
            continuations.removeValue(forKey: identifier)?.finish()
        }
        return try await walletFulcrumReadinessBounded(description) {
            for await values in pair.stream where predicate(values) { return values }
            throw CancellationError()
        }
    }
}

func walletFulcrumReadinessBounded<Value: Sendable>(
    _ description: String,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            // This is a failure deadline, not synchronization or an observation delay.
            try await Task.sleep(for: .seconds(10))
            throw WalletFulcrumReadinessTestFailure.timedOut(description)
        }
        defer { group.cancelAll() }
        guard let value = try await group.next() else { throw CancellationError() }
        return value
    }
}

actor WalletFulcrumReadinessAddressClient: OpalBase.Network.AddressReadable {
    enum Query: Sendable {
        case subscription(String)
        case subscriptionReady(String)
        case unspent(String)
        case history(String, includeUnconfirmed: Bool)
        case terminated(String)
    }

    enum Reply<Value: Sendable>: Sendable {
        case value(Value)
        case failure(String)
        case held(WalletFulcrumReadinessQueryGate<Value>)

        func resolve() async throws -> Value {
            switch self {
            case .value(let value): return value
            case .failure(let message): throw WalletFulcrumReadinessTestFailure.forced(message)
            case .held(let gate): return try await gate.value()
            }
        }
    }

    let queries = WalletFulcrumReadinessProbe<Query>()
    private var subscriptions: [String: AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, Swift.Error>.Continuation] = [:]
    private var subscriptionGates: [String: WalletFulcrumReadinessQueryGate<Void>] = [:]
    private var unspentReplies: [String: [Reply<[OpalBase.Transaction.Output.Unspent]>]] = [:]
    private var cancelledSetups: Set<String> = []
    private var updateSequences: [String: Int] = [:]
    private var historyReplies: [String: [Reply<[OpalBase.Network.TransactionHistoryEntry]>]] = [:]

    func cancelNextSetup(_ address: String) { cancelledSetups.insert(address) }

    func holdSubscription(_ address: String, using gate: WalletFulcrumReadinessQueryGate<Void>) {
        subscriptionGates[address] = gate
    }

    func setUnspentReplies(_ replies: [Reply<[OpalBase.Transaction.Output.Unspent]>], for address: String) {
        unspentReplies[address] = replies
    }

    func setHistoryReplies(_ replies: [Reply<[OpalBase.Network.TransactionHistoryEntry]>], for address: String) {
        historyReplies[address] = replies
    }

    func sendUpdate(_ address: String) {
        updateSequences[address, default: 0] += 1
        sendUpdate(address, status: "controlled-update-\(updateSequences[address]!)")
    }

    func sendUpdate(_ address: String, status: String?, generation: UInt64? = nil) {
        subscriptions[address]?.yield(.init(kind: .change, address: address, status: status, connectionGeneration: generation))
    }

    func finishSubscription(_ address: String) { subscriptions[address]?.finish() }

    func failSubscription(_ address: String) {
        subscriptions[address]?.finish(throwing: WalletFulcrumReadinessTestFailure.forced("address subscription ended"))
    }

    func fetchBalance(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> OpalBase.Network.AddressBalance {
        .init(confirmed: 0, unconfirmed: 0)
    }

    func fetchUnspentOutputs(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> [OpalBase.Transaction.Output.Unspent] {
        let reply = unspentReplies[address]?.isEmpty == false ? unspentReplies[address]!.removeFirst() : .value([])
        await queries.append(.unspent(address))
        return try await reply.resolve()
    }

    func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
        let reply = historyReplies[address]?.isEmpty == false ? historyReplies[address]!.removeFirst() : .value([])
        await queries.append(.history(address, includeUnconfirmed: includeUnconfirmed))
        return try await reply.resolve()
    }

    func fetchFirstUse(for address: String) async throws -> OpalBase.Network.AddressFirstUse? { nil }
    func fetchMempoolTransactions(for address: String) async throws -> [OpalBase.Network.TransactionHistoryEntry] { [] }
    func fetchScriptHash(for address: String) async throws -> String { "" }

    func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, Swift.Error> {
        let gate = subscriptionGates.removeValue(forKey: address)
        await queries.append(.subscription(address))
        if cancelledSetups.remove(address) != nil { throw CancellationError() }
        if let gate { _ = try await gate.value() }
        let pair = AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, Swift.Error>.makeStream()
        subscriptions[address] = pair.continuation
        pair.continuation.onTermination = { [queries] _ in
            Task { await queries.append(.terminated(address)) }
        }
        await queries.append(.subscriptionReady(address))
        return pair.stream
    }
}

extension WalletFulcrumReadinessAddressClient.Query {
    static func subscriptionCount(_ address: String, in queries: [Self]) -> Int {
        queries.filter { if case .subscription(let candidate) = $0 { candidate == address } else { false } }.count
    }

    static func unspentCount(_ address: String, in queries: [Self]) -> Int {
        queries.filter { if case .unspent(let candidate) = $0 { candidate == address } else { false } }.count
    }

    static func historyCount(_ address: String, in queries: [Self]) -> Int {
        queries.filter { if case .history(let candidate, _) = $0 { candidate == address } else { false } }.count
    }
}

actor WalletFulcrumReadinessHeaderClient: OpalBase.Network.BlockHeaderReadable {
    private var continuation: AsyncThrowingStream<OpalBase.Network.BlockHeaderSnapshot, Swift.Error>.Continuation?
    private(set) var subscriptionCount = 0

    func fetchTip() async throws -> OpalBase.Network.BlockHeaderSnapshot {
        .init(height: 1, headerHexadecimal: String(repeating: "0", count: 160))
    }

    func subscribeToTip() async throws -> AsyncThrowingStream<OpalBase.Network.BlockHeaderSnapshot, Swift.Error> {
        subscriptionCount += 1
        let pair = AsyncThrowingStream<OpalBase.Network.BlockHeaderSnapshot, Swift.Error>.makeStream()
        continuation = pair.continuation
        return pair.stream
    }

    func fail() {
        continuation?.finish(throwing: WalletFulcrumReadinessTestFailure.forced("header subscription failed"))
    }
}
