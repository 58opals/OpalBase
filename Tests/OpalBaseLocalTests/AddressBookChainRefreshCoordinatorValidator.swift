import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("Address book refresh ownership", .tags(.unit, .wallet))
struct AddressBookChainRefreshCoordinatorValidator {
    @Test("A held address orders its own updates while another address progresses")
    func sameAddressIsOrderedWhileIndependentAddressProgresses() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addresses = await account.listTrackedEntries().map(\.address)
        let coordinator = await account.addressBook.chainRefreshCoordinator
        let entered = WalletFulcrumReadinessProbe<String>()
        let held = WalletFulcrumReadinessQueryGate<Void>()
        let first = Task {
            try await coordinator.performForAddress(addresses[0]) {
                await entered.append("first")
                _ = try await held.value()
            }
        }
        defer { held.succeed(()); first.cancel() }
        _ = try await entered.wait("first address holds ownership") { $0 == ["first"] }
        let sameAddress = Task {
            try await coordinator.performForAddress(addresses[0]) { await entered.append("same-address") }
        }
        defer { sameAddress.cancel() }
        try await waitForQueueCount(1, coordinator: coordinator)
        let independent = Task {
            try await coordinator.performForAddress(addresses[1]) { await entered.append("independent") }
        }
        defer { independent.cancel() }
        _ = try await entered.wait("independent address completes before the held address") { $0.contains("independent") }
        try await independent.value
        #expect(await entered.snapshot() == ["first", "independent"])
        #expect(await coordinator.queuedOperationCount == 1)
        held.succeed(())
        try await first.value
        try await sameAddress.value
        #expect(await entered.snapshot() == ["first", "independent", "same-address"])
    }

    @Test("Four address slots drain before a queued full refresh and later addresses")
    func boundedAddressesRespectExclusiveFairness() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addresses = await account.listTrackedEntries().map(\.address)
        let coordinator = await account.addressBook.chainRefreshCoordinator
        let entered = WalletFulcrumReadinessProbe<String>()
        let gates = (0..<5).map { _ in WalletFulcrumReadinessQueryGate<Void>() }
        let initial = (0..<4).map { index in
            Task {
                try await coordinator.performForAddress(addresses[index]) {
                    await entered.append("address-\(index)")
                    _ = try await gates[index].value()
                }
            }
        }
        defer {
            for gate in gates { gate.succeed(()) }
            for task in initial { task.cancel() }
        }
        _ = try await entered.wait("four distinct address operations hold every slot") { $0.count == 4 }
        let fifth = Task {
            try await coordinator.performForAddress(addresses[4]) {
                await entered.append("fifth")
                _ = try await gates[4].value()
            }
        }
        defer { fifth.cancel() }
        try await waitForQueueCount(1, coordinator: coordinator)
        let fullGate = WalletFulcrumReadinessQueryGate<Void>()
        let full = Task {
            try await coordinator.performExclusively {
                await entered.append("full")
                _ = try await fullGate.value()
            }
        }
        defer { fullGate.succeed(()); full.cancel() }
        try await waitForQueueCount(2, coordinator: coordinator)
        let late = Task {
            try await coordinator.performForAddress(addresses[5]) { await entered.append("late") }
        }
        defer { late.cancel() }
        try await waitForQueueCount(3, coordinator: coordinator)
        #expect(await entered.snapshot().count == 4)
        gates[0].succeed(())
        _ = try await entered.wait("the earlier fifth address takes the released slot") { $0.contains("fifth") }
        for index in 1..<4 { gates[index].succeed(()) }
        for task in initial { try await task.value }
        #expect(await coordinator.queuedOperationCount == 2)
        #expect(await entered.snapshot().count == 5)
        gates[4].succeed(())
        try await fifth.value
        _ = try await entered.wait("full refresh starts after every earlier address drains") { $0.last == "full" }
        #expect(await coordinator.queuedOperationCount == 1)
        fullGate.succeed(())
        try await full.value
        try await late.value
        #expect(Array(await entered.snapshot().suffix(3)) == ["fifth", "full", "late"])
    }

    @Test("Cancelling a queued address never runs it or releases another operation")
    func queuedAddressCancellationPreservesOwnership() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let address = try #require(await account.listTrackedEntries().first?.address)
        let coordinator = await account.addressBook.chainRefreshCoordinator
        let entered = WalletFulcrumReadinessProbe<String>()
        let held = WalletFulcrumReadinessQueryGate<Void>()
        let full = Task {
            try await coordinator.performExclusively {
                await entered.append("full")
                _ = try await held.value()
            }
        }
        defer { held.succeed(()); full.cancel() }
        _ = try await entered.wait("full refresh holds ownership") { $0 == ["full"] }
        let cancelled = Task {
            try await coordinator.performForAddress(address) { await entered.append("cancelled") }
        }
        defer { cancelled.cancel() }
        try await waitForQueueCount(1, coordinator: coordinator)
        cancelled.cancel()
        switch await cancelled.result {
        case .success: Issue.record("Cancelled queued address operation unexpectedly succeeded")
        case .failure(let error): #expect(error is CancellationError)
        }
        #expect(await coordinator.queuedOperationCount == 0)
        let next = Task {
            try await coordinator.performForAddress(address) { await entered.append("next") }
        }
        defer { next.cancel() }
        try await waitForQueueCount(1, coordinator: coordinator)
        #expect(await entered.snapshot() == ["full"])
        held.succeed(())
        try await full.value
        try await next.value
        #expect(await entered.snapshot() == ["full", "next"])
    }

    private func waitForQueueCount(
        _ count: Int,
        coordinator: OpalBase.Address.Book.ChainRefreshCoordinator
    ) async throws {
        try await walletFulcrumReadinessBounded("refresh queue admits \(count) waiting operations") {
            while await coordinator.queuedOperationCount != count {
                try Task.checkCancellation()
                await Task.yield()
            }
        }
    }
}
