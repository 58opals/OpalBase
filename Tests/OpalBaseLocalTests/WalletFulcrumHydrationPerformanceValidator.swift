import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

private typealias HydrationMonitor = OpalBase.Wallet.Fulcrum.Monitor
private struct HydrationObservation: Sendable {
    let accountIndex: Int
    let value: HydrationMonitor.Observation
    let observedAt: ContinuousClock.Instant
}
private typealias HydrationObservations = WalletFulcrumReadinessProbe<HydrationObservation>

@Suite("Controlled account hydration workload", .serialized, .tags(.integration, .wallet))
struct WalletFulcrumHydrationPerformanceValidator {
    @Test("Default forty-address startup and reconnect report work and independent progress", .timeLimit(.minutes(1)))
    func defaultScopeStartupAndReconnectWorkload() async throws {
        try await runWorkload(accountCount: 1)
    }

    @Test("Three default accounts report per-account and aggregate startup and reconnect work", .timeLimit(.minutes(1)))
    func threeAccountStartupAndReconnectWorkload() async throws {
        try await runWorkload(accountCount: 3)
    }

    private func runWorkload(accountCount: Int) async throws {
        let wallet = try await AccountTestFixtures.makeWallet(accountIndices: (0..<accountCount).map(UInt32.init))
        var accounts: [OpalBase.Account] = []
        var addressesByAccount: [[OpalBase.Address]] = []
        for index in 0..<accountCount {
            let account = try await wallet.fetchAccount(at: UInt32(index))
            accounts.append(account)
            let addresses = await account.listTrackedEntries().map(\.address)
            #expect(await account.addressBook.readGapLimit() == 20)
            #expect(addresses.count == 40)
            addressesByAccount.append(addresses)
        }
        let addresses = addressesByAccount.flatMap { $0 }
        let slowAddress = try #require(addresses.first)
        let accountIndexByAddress = Dictionary(uniqueKeysWithValues: addressesByAccount.enumerated().flatMap { index, addresses in
            addresses.map { ($0.string, index) }
        })
        let client = HydrationWorkloadAddressClient(accountIndexByAddress: accountIndexByAddress)
        let connections = accounts.map { _ in AsyncStream<OpalBase.Network.Fulcrum.Client.ConnectionRecoveryObservation>.makeStream() }
        let monitors = accounts.enumerated().map { index, account in
            HydrationMonitor(account: account, addressReader: .init(client),
                blockHeaderReader: .init(WalletFulcrumReadinessHeaderClient()),
                transactionClient: .init(confirmations: TransactionConfirmationClientTestActor()),
                monitorsBlockHeaders: false, connectionRecoveryStates: connections[index].stream)
        }
        let observations = HydrationObservations()
        var collectors: [Task<Void, Swift.Error>] = []
        for (index, monitor) in monitors.enumerated() {
            let stream = await monitor.makeObservationStream(autoStart: false)
            collectors.append(Task {
                for try await observation in stream {
                    await observations.append(.init(accountIndex: index, value: observation, observedAt: ContinuousClock().now))
                }
            })
        }
        let clock = ContinuousClock()
        do {
            let startupStarted = clock.now
            await withTaskGroup(of: Void.self) { group in
                for monitor in monitors { group.addTask { await monitor.start() } }
            }
            #expect(await client.subscriptionCount == addresses.count)
            try await measurePhase("startup", started: startupStarted, addressesByAccount: addressesByAccount,
                slowAddress: slowAddress, client: client, observations: observations)

            let reconnectStarted = clock.now
            for (index, monitor) in monitors.enumerated() {
                let oldGeneration = await monitor.eventHub.makeMutationPermit()
                connections[index].continuation.yield(.init(generation: 1, sequence: 1, state: .recovering))
                try await walletFulcrumReadinessBounded("reconnect invalidates each hydrated generation") {
                    while oldGeneration.isCurrent {
                        try Task.checkCancellation()
                        await Task.yield()
                    }
                }
            }
            for connection in connections { connection.continuation.yield(.init(generation: 1, sequence: 2, state: .ready)) }
            try await measurePhase("reconnect", started: reconnectStarted, addressesByAccount: addressesByAccount,
                slowAddress: slowAddress, client: client, observations: observations)
            #expect(await client.subscriptionCount == addresses.count)
            for account in accounts {
                #expect(await account.loadTransactionHistory().isEmpty)
                #expect(await account.addressBook.listUTXOs().isEmpty)
            }
            for monitor in monitors { await monitor.stop() }
            for connection in connections { connection.continuation.finish() }
            for collector in collectors { try await collector.value }
        } catch {
            for monitor in monitors { await monitor.stop() }
            for connection in connections { connection.continuation.finish() }
            for collector in collectors { collector.cancel(); _ = await collector.result }
            throw error
        }
    }

    private func measurePhase(
        _ phase: String,
        started: ContinuousClock.Instant,
        addressesByAccount: [[OpalBase.Address]],
        slowAddress: OpalBase.Address,
        client: HydrationWorkloadAddressClient,
        observations: HydrationObservations
    ) async throws {
        let before = await observations.snapshot()
        let addresses = addressesByAccount.flatMap { $0 }
        let accountCount = addressesByAccount.count
        let readyBefore = (0..<accountCount).map { Self.readyCount(before, accountIndex: $0) }
        let publicationsBefore = (0..<accountCount).map { Self.utxoPublicationCount(before, accountIndex: $0) }
        let slowQuery = WalletFulcrumReadinessQueryGate<Void>()
        await client.preparePhase(slowAddress: slowAddress.string, gate: slowQuery)
        defer { slowQuery.succeed(()) }
        await client.sendUpdate(slowAddress.string)
        _ = try await client.queryStarts.wait("slow address occupies its hydration operation") { !$0.isEmpty }
        for address in addresses where address != slowAddress { await client.sendUpdate(address.string) }

        // These are declared benchmark inputs, never correctness deadlines or barriers.
        // The first query remains causally held while other addresses can make progress.
        try await Task.sleep(for: .milliseconds(200))
        let held = await client.metrics()
        let heldObservations = await observations.snapshot()
        let independentPublications = (0..<accountCount).map {
            Self.utxoPublicationCount(heldObservations, accountIndex: $0) - publicationsBefore[$0]
        }
        slowQuery.succeed(())
        let ready = try await observations.wait("complete all default-account \(phase) hydrations") { values in
            (0..<accountCount).allSatisfy { Self.readyCount(values, accountIndex: $0) > readyBefore[$0] }
        }
        let final = await client.metrics()
        #expect(final.aggregate.activeQueries == 0)
        #expect(final.aggregate.unspentQueries == addresses.count)
        #expect(final.aggregate.historyQueries == addresses.count)
        #expect(final.aggregate.completedHistories == addresses.count)
        let perAccount = try (0..<accountCount).map { index in
            let metrics = try #require(final.byAccount[index])
            #expect(metrics.unspentQueries == addressesByAccount[index].count)
            #expect(metrics.historyQueries == addressesByAccount[index].count)
            #expect(Self.utxoPublicationCount(ready, accountIndex: index) - publicationsBefore[index] == addressesByAccount[index].count)
            let lastReady = try #require(ready.last { observation in
                guard observation.accountIndex == index else { return false }
                if case .state(.synchronized) = observation.value { return true }
                return false
            })
            return HydrationAccountReport(accountIndex: index,
                readinessMilliseconds: Self.milliseconds(started.duration(to: lastReady.observedAt)),
                peakActiveQueries: metrics.peakActiveQueries, unspentQueries: metrics.unspentQueries,
                historyQueries: metrics.historyQueries,
                independentHistoriesCompletedWhileSlowAddressHeld: held.byAccount[index]?.completedHistories ?? 0,
                independentPublicationsWhileSlowAddressHeld: independentPublications[index])
        }
        let report = HydrationWorkloadReport(
            phase: phase,
            accountCount: accountCount,
            addressCount: addresses.count,
            queryDelayMilliseconds: 50,
            slowAddressHoldMilliseconds: 200,
            readinessMilliseconds: Self.milliseconds(started.duration(to: ContinuousClock().now)),
            peakActiveQueries: final.aggregate.peakActiveQueries,
            unspentQueries: final.aggregate.unspentQueries,
            historyQueries: final.aggregate.historyQueries,
            independentHistoriesCompletedWhileSlowAddressHeld: held.aggregate.completedHistories,
            independentPublicationsWhileSlowAddressHeld: independentPublications.reduce(0, +),
            perAccount: perAccount
        )
        let data = try JSONEncoder().encode(report)
        print("HYDRATION_WORKLOAD \(String(decoding: data, as: UTF8.self))")
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let elapsed = duration.components
        return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
    }

    private static func readyCount(_ values: [HydrationObservation], accountIndex: Int) -> Int {
        values.filter { value in
            guard value.accountIndex == accountIndex else { return false }
            if case .state(.synchronized) = value.value { return true }
            return false
        }.count
    }

    private static func utxoPublicationCount(_ values: [HydrationObservation], accountIndex: Int) -> Int {
        values.filter { value in
            guard value.accountIndex == accountIndex else { return false }
            if case .event(.utxosChanged) = value.value { return true }
            return false
        }.count
    }
}

private struct HydrationWorkloadReport: Encodable {
    let phase: String
    let accountCount: Int
    let addressCount: Int
    let queryDelayMilliseconds: Int
    let slowAddressHoldMilliseconds: Int
    let readinessMilliseconds: Double
    let peakActiveQueries: Int
    let unspentQueries: Int
    let historyQueries: Int
    let independentHistoriesCompletedWhileSlowAddressHeld: Int
    let independentPublicationsWhileSlowAddressHeld: Int
    let perAccount: [HydrationAccountReport]
}

private struct HydrationAccountReport: Encodable {
    let accountIndex: Int
    let readinessMilliseconds: Double
    let peakActiveQueries: Int
    let unspentQueries: Int
    let historyQueries: Int
    let independentHistoriesCompletedWhileSlowAddressHeld: Int
    let independentPublicationsWhileSlowAddressHeld: Int
}

private actor HydrationWorkloadAddressClient: OpalBase.Network.AddressReadable {
    struct Metrics: Sendable {
        var activeQueries = 0
        var peakActiveQueries = 0
        var unspentQueries = 0
        var historyQueries = 0
        var completedHistories = 0
    }

    struct PhaseMetrics: Sendable {
        var aggregate = Metrics()
        var byAccount: [Int: Metrics] = [:]
    }

    private var subscriptions: [String: AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, Swift.Error>.Continuation] = [:]
    private var slowQuery: (address: String, gate: WalletFulcrumReadinessQueryGate<Void>)?
    private let accountIndexByAddress: [String: Int]
    private var phaseMetrics = PhaseMetrics()
    private(set) var subscriptionCount = 0
    private(set) var queryStarts = WalletFulcrumReadinessProbe<String>()

    init(accountIndexByAddress: [String: Int]) { self.accountIndexByAddress = accountIndexByAddress }

    func preparePhase(slowAddress: String, gate: WalletFulcrumReadinessQueryGate<Void>) {
        phaseMetrics = PhaseMetrics()
        queryStarts = WalletFulcrumReadinessProbe<String>()
        slowQuery = (slowAddress, gate)
    }

    func metrics() -> PhaseMetrics { phaseMetrics }

    func sendUpdate(_ address: String) {
        subscriptions[address]?.yield(.init(kind: .change, address: address, status: "controlled-workload"))
    }

    func fetchUnspentOutputs(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> [OpalBase.Transaction.Output.Unspent] {
        beginQuery(address: address)
        changeMetrics(for: address) { $0.unspentQueries += 1 }
        defer { changeMetrics(for: address) { $0.activeQueries -= 1 } }
        let gate = slowQuery?.address == address ? slowQuery?.gate : nil
        if gate != nil { slowQuery = nil }
        await queryStarts.append(address)
        if let gate { _ = try await gate.value() }
        try await Task.sleep(for: .milliseconds(50))
        return []
    }

    func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
        beginQuery(address: address)
        changeMetrics(for: address) { $0.historyQueries += 1 }
        defer { changeMetrics(for: address) { $0.activeQueries -= 1 } }
        try await Task.sleep(for: .milliseconds(50))
        changeMetrics(for: address) { $0.completedHistories += 1 }
        return []
    }

    private func beginQuery(address: String) {
        changeMetrics(for: address) {
            $0.activeQueries += 1
            $0.peakActiveQueries = max($0.peakActiveQueries, $0.activeQueries)
        }
    }

    private func changeMetrics(for address: String, _ mutation: (inout Metrics) -> Void) {
        mutation(&phaseMetrics.aggregate)
        if let index = accountIndexByAddress[address] { mutation(&phaseMetrics.byAccount[index, default: Metrics()]) }
    }

    func fetchBalance(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> OpalBase.Network.AddressBalance { .init(confirmed: 0, unconfirmed: 0) }
    func fetchFirstUse(for address: String) async throws -> OpalBase.Network.AddressFirstUse? { nil }
    func fetchMempoolTransactions(for address: String) async throws -> [OpalBase.Network.TransactionHistoryEntry] { [] }
    func fetchScriptHash(for address: String) async throws -> String { "" }

    func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, Swift.Error> {
        subscriptionCount += 1
        let pair = AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, Swift.Error>.makeStream()
        subscriptions[address] = pair.continuation
        return pair.stream
    }
}
