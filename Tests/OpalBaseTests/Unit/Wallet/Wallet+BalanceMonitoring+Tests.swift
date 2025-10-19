import Foundation
import Testing
@testable import OpalBase

@Suite("Wallet Balance Monitoring", .tags(.unit, .wallet))
struct WalletBalanceMonitoringSuite {
    @Test("aggregates account balance updates across lifecycle transitions", .tags(.unit, .wallet))
    func aggregatesBalancesDuringLifecycle() async throws {
        let coordinator = Lifecycle.Coordinator<Satoshi>()
        let aggregator = BalanceAggregator()
        let savings = BalanceSource(label: "savings", aggregator: aggregator)
        let spending = BalanceSource(label: "spending", aggregator: aggregator)
        
        _ = await coordinator.register(label: "wallet-account-savings", hooks: savings.makeHooks())
        _ = await coordinator.register(label: "wallet-account-spending", hooks: spending.makeHooks())
        
        let stream = try await coordinator.start()
        var iterator = stream.makeAsyncIterator()
        
        let savingsInitial = try Satoshi(150_000_000)  // 1.50 BCH
        await savings.send(savingsInitial)
        let first = try await iterator.next()
        #expect(first == savingsInitial)
        
        let spendingInitial = try Satoshi(25_000_000)  // 0.25 BCH
        await spending.send(spendingInitial)
        let combinedInitial = try savingsInitial + spendingInitial
        let second = try await iterator.next()
        #expect(second == combinedInitial)
        
        let savingsTopUp = try Satoshi(180_000_000)  // 1.80 BCH
        await savings.send(savingsTopUp)
        let afterTopUp = try savingsTopUp + spendingInitial
        let third = try await iterator.next()
        #expect(third == afterTopUp)
        
        try await coordinator.suspend()
        
        let spendingPayroll = try Satoshi(45_000_000)  // 0.45 BCH
        await spending.send(spendingPayroll)
        let pausedTotal = try await aggregator.currentTotal()
        #expect(pausedTotal == afterTopUp)
        
        try await coordinator.resume()
        let resumed = try await iterator.next()
        let afterPayroll = try savingsTopUp + spendingPayroll
        #expect(resumed == afterPayroll)
        
        await savings.finish()
        await spending.finish()
        #expect(try await iterator.next() == nil)
        
        let finalTotal = try await aggregator.currentTotal()
        #expect(finalTotal == Satoshi())
    }
}

private actor BalanceAggregator {
    private var balances: [UUID: Satoshi] = .init()
    
    func updateBalance(_ balance: Satoshi, for accountID: UUID) async throws -> Satoshi {
        balances[accountID] = balance
        return try currentTotal()
    }
    
    func removeBalance(for accountID: UUID) {
        balances.removeValue(forKey: accountID)
    }
    
    func currentTotal() throws -> Satoshi {
        var total = Satoshi()
        for value in balances.values {
            total = try total + value
        }
        return total
    }
}

private actor BalanceSource {
    enum Error: Swift.Error {
        case ownerReleased
    }
    
    let label: String
    private let identifier = UUID()
    private let aggregator: BalanceAggregator
    private let sourceStream: AsyncThrowingStream<Satoshi, Swift.Error>
    private let sourceContinuation: AsyncThrowingStream<Satoshi, Swift.Error>.Continuation
    private var lifecycleContinuation: AsyncThrowingStream<Satoshi, Swift.Error>.Continuation?
    private var isSuspended = false
    private var pendingBalance: Satoshi?
    
    init(label: String, aggregator: BalanceAggregator) {
        self.label = label
        self.aggregator = aggregator
        var continuation: AsyncThrowingStream<Satoshi, Swift.Error>.Continuation?
        self.sourceStream = AsyncThrowingStream { streamContinuation in
            continuation = streamContinuation
        }
        guard let continuation else { fatalError("Failed to create balance stream continuation") }
        self.sourceContinuation = continuation
    }
    
    func makeHooks() -> Lifecycle.Coordinator<Satoshi>.Hooks {
        .init(
            start: { [weak self] in
                guard let self else { throw Error.ownerReleased }
                return await self.makeLifecycleStream()
            },
            suspend: { [weak self] in
                guard let self else { return }
                await self.setSuspended(true)
            },
            resume: { [weak self] in
                guard let self else { throw Error.ownerReleased }
                try await self.resumeFromSuspension()
            },
            shutdown: { [weak self] in
                guard let self else { return }
                await self.shutdown()
            }
        )
    }
    
    func send(_ balance: Satoshi) {
        sourceContinuation.yield(balance)
    }
    
    func finish() {
        sourceContinuation.finish()
    }
    
    private func makeLifecycleStream() -> AsyncThrowingStream<Satoshi, Swift.Error> {
        let stream = sourceStream
        return AsyncThrowingStream { continuation in
            Task { self.attach(continuation: continuation) }
            let task = Task {
                do {
                    for try await balance in stream {
                        try await self.forward(balance: balance)
                    }
                    self.detach()
                    continuation.finish()
                } catch is CancellationError {
                    self.detach()
                    continuation.finish()
                } catch {
                    self.detach()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    private func attach(continuation: AsyncThrowingStream<Satoshi, Swift.Error>.Continuation) {
        lifecycleContinuation = continuation
    }
    
    private func detach() {
        lifecycleContinuation = nil
        pendingBalance = nil
        isSuspended = false
    }
    
    private func forward(balance: Satoshi) async throws {
        if isSuspended {
            pendingBalance = balance
            return
        }
        pendingBalance = nil
        let total = try await aggregator.updateBalance(balance, for: identifier)
        lifecycleContinuation?.yield(total)
    }
    
    private func setSuspended(_ flag: Bool) {
        isSuspended = flag
    }
    
    private func resumeFromSuspension() async throws {
        guard isSuspended else { return }
        isSuspended = false
        if let pendingBalance {
            self.pendingBalance = nil
            let total = try await aggregator.updateBalance(pendingBalance, for: identifier)
            lifecycleContinuation?.yield(total)
        }
    }
    
    private func shutdown() async {
        lifecycleContinuation = nil
        pendingBalance = nil
        isSuspended = false
        await aggregator.removeBalance(for: identifier)
    }
}
