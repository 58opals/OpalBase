import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

private typealias ReadinessMonitor = OpalBase.Wallet.Fulcrum.Monitor
private typealias ReadinessObservation = ReadinessMonitor.Observation
private typealias ReadinessQuery = WalletFulcrumReadinessAddressClient.Query
private typealias ReadinessObservations = WalletFulcrumReadinessProbe<ReadinessObservation>

@Suite("Account monitoring readiness", .tags(.unit, .wallet))
struct WalletFulcrumMonitoringReadinessValidator {
    @Test("Empty public history becomes ready only after every real address hydration")
    func emptyHistorySuccessRequiresHydration() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addresses = await account.listTrackedEntries().map(\.address)
        let client = WalletFulcrumReadinessAddressClient()
        let header = WalletFulcrumReadinessHeaderClient()
        let monitor = makeMonitor(account, client: client, header: header)
        try await withObservations(monitor) { observations in
            await monitor.start()
            #expect(Self.readyCount(await observations.snapshot()) == 0)
            let registered = await client.queries.snapshot()
            #expect(addresses.allSatisfy { ReadinessQuery.subscriptionCount($0.string, in: registered) == 1 })
            #expect(registered.allSatisfy {
                switch $0 {
                case .subscription, .subscriptionReady: true
                default: false
                }
            })
            for address in addresses { await client.sendUpdate(address.string) }
            _ = try await observations.wait("every empty address hydrated") { Self.readyCount($0) > 0 }
            let queries = await client.queries.snapshot()
            #expect(addresses.allSatisfy { ReadinessQuery.unspentCount($0.string, in: queries) == 1 })
            #expect(addresses.allSatisfy { ReadinessQuery.historyCount($0.string, in: queries) == 1 })
            #expect(queries.allSatisfy { if case .history(_, let includesPending) = $0 { includesPending } else { true } })
            #expect(await account.loadTransactionHistory().isEmpty)
            #expect(await account.addressBook.listUTXOs().isEmpty)
            #expect(await header.subscriptionCount == 0)
        }
    }

    @Test("Another address's successful hydration cannot clear a failed address")
    func failedAddressRequiresItsOwnRecovery() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addresses = await account.listTrackedEntries().map(\.address)
        let receiving = await account.listEntries(for: .receiving).map(\.address)
        let first = try #require(receiving.first)
        let second = try #require(receiving.dropFirst().first)
        let client = WalletFulcrumReadinessAddressClient()
        await client.setUnspentReplies([.failure("first address unavailable"), .failure("fallback also unavailable")], for: first.string)
        let monitor = makeMonitor(account, client: client)
        try await withObservations(monitor) { observations in
            await monitor.start()
            await client.sendUpdate(first.string)
            _ = try await observations.wait("address failure reaches public stream") { Self.lastFailure($0)?.address == first }
            _ = try await observations.wait("failed fallback is reported") { values in
                values.filter {
                    if case .event(.encounteredFailure(let failure)) = $0 { failure.address == first } else { false }
                }.count >= 2
            }
            let secondQueriesBefore = ReadinessQuery.unspentCount(second.string, in: await client.queries.snapshot())
            let nextUpdate = WalletFulcrumReadinessQueryGate<[OpalBase.Transaction.Output.Unspent]>()
            await client.setUnspentReplies([.value([]), .held(nextUpdate)], for: second.string)
            await client.sendUpdate(second.string)
            await client.sendUpdate(second.string)
            // A subscription consumes updates serially: entering the second query proves
            // its previous real hydration and readiness publication have completed.
            _ = try await client.queries.wait("unrelated address completed hydration") {
                ReadinessQuery.unspentCount(second.string, in: $0) == secondQueriesBefore + 2
            }
            #expect(Self.lastFailure(await observations.snapshot())?.address == first)
            if case .failed(let failure) = try await currentState(monitor) {
                #expect(failure.address == first)
            } else {
                Issue.record("Successful hydration of another address cleared the failed address")
            }
            #expect(Self.readyCount(await observations.snapshot()) == 0)
            nextUpdate.succeed([])
            for address in addresses { await client.sendUpdate(address.string) }
            _ = try await observations.wait("same address recovers and all addresses are hydrated") { Self.readyCount($0) > 0 }
            #expect(Self.lastStateIsReady(await observations.snapshot()))
            #expect(await account.loadTransactionHistory().isEmpty)
            let queries = await client.queries.snapshot()
            #expect(ReadinessQuery.unspentCount(first.string, in: queries) >= 3)
            #expect(ReadinessQuery.historyCount(first.string, in: queries) >= 1)
        }
    }

    @Test("A generated address during startup is subscribed exactly once")
    func generatedAddressDuringStartupIsNotMissedOrDuplicated() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let existing = await account.listTrackedEntries().map(\.address)
        let first = try #require(existing.first)
        let client = WalletFulcrumReadinessAddressClient()
        let startup = WalletFulcrumReadinessQueryGate<Void>()
        await client.holdSubscription(first.string, using: startup)
        let monitor = makeMonitor(account, client: client)
        try await withObservations(monitor) { observations in
            let start = Task { await monitor.start() }
            do {
                _ = try await client.queries.wait("first subscription entered startup") {
                    ReadinessQuery.subscriptionCount(first.string, in: $0) == 1
                }
                try await account.addressBook.generateEntries(for: .receiving, entryCount: 1, isUsed: false)
                let all = await account.listTrackedEntries().map(\.address)
                let generated = try #require(all.first { !existing.contains($0) })
                _ = try await client.queries.wait("new entry reaches real subscriber during startup") {
                    ReadinessQuery.subscriptionCount(generated.string, in: $0) >= 1
                }
                startup.succeed(())
                await start.value
                _ = try await client.queries.wait("generated subscription is ready to receive updates") { queries in
                    queries.contains { if case .subscriptionReady(let value) = $0 { value == generated.string } else { false } }
                }
                for address in all { await client.sendUpdate(address.string) }
                _ = try await observations.wait("generated scope is fully hydrated") { Self.readyCount($0) > 0 }
                let queries = await client.queries.snapshot()
                #expect(all.allSatisfy { ReadinessQuery.subscriptionCount($0.string, in: queries) == 1 })
                let tracked = await observations.snapshot().filter {
                    if case .event(.addressTracked(let address)) = $0 { address == generated } else { false }
                }
                #expect(tracked.count == 1)
            } catch {
                startup.fail("startup test cancelled")
                start.cancel()
                await start.value
                throw error
            }
        }
    }

    @Test("Reconnect prevents obsolete hydration from changing the actual address book", arguments: [false, true])
    func reconnectFencesHydration(fullFallback: Bool) async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addresses = await account.listTrackedEntries().map(\.address)
        let first = try #require(addresses.first)
        let client = WalletFulcrumReadinessAddressClient()
        let connections = AsyncStream<OpalBase.Network.Fulcrum.Client.ConnectionRecoveryObservation>.makeStream()
        let monitor = makeMonitor(account, client: client, connectionRecoveryStates: connections.stream)
        defer { connections.continuation.finish() }
        try await withObservations(monitor) { observations in
            await monitor.start()
            for address in addresses { await client.sendUpdate(address.string) }
            _ = try await observations.wait("initial generation hydrated") { Self.readyCount($0) > 0 }
            let before = await account.makeSnapshot().addressBook
            let readyBefore = Self.readyCount(await observations.snapshot())
            let oldOutput = OpalBase.Transaction.Output.Unspent(value: 654,
                lockingScript: first.lockingScript.data,
                previousTransactionHash: AccountTestFixtures.makeHash(byte: 0xc1), previousTransactionOutputIndex: 0)
            let historyGate = WalletFulcrumReadinessQueryGate<[OpalBase.Network.TransactionHistoryEntry]>()
            let unspentGate = WalletFulcrumReadinessQueryGate<[OpalBase.Transaction.Output.Unspent]>()
            if fullFallback {
                await client.setUnspentReplies([.failure("start fallback"), .held(unspentGate)], for: first.string)
            } else {
                await client.setUnspentReplies([.value([oldOutput])], for: first.string)
                await client.setHistoryReplies([.held(historyGate)], for: first.string)
            }
            // This read-only epoch snapshot is a causal barrier, never a test-driven
            // mutation of the monitor hub. The public connection stream invalidates it.
            let previousGeneration = await monitor.eventHub.makeMutationPermit()
            await client.sendUpdate(first.string)
            _ = try await client.queries.wait("obsolete public query is held") {
                fullFallback ? ReadinessQuery.unspentCount(first.string, in: $0) == 3 : ReadinessQuery.historyCount(first.string, in: $0) == 2
            }
            connections.continuation.yield(.init(generation: 1, sequence: 1, state: .recovering))
            try await walletFulcrumReadinessBounded("connection invalidated the held query") {
                while previousGeneration.isCurrent {
                    try Task.checkCancellation()
                    await Task.yield()
                }
            }
            connections.continuation.yield(.init(generation: 1, sequence: 2, state: .ready))
            if fullFallback { unspentGate.succeed([oldOutput]) }
            else { historyGate.succeed([AccountTestFixtures.makeHistoryEntry(hashByte: 0xc2, blockHeight: 123)]) }
            let nextUpdate = WalletFulcrumReadinessQueryGate<[OpalBase.Transaction.Output.Unspent]>()
            await client.setUnspentReplies([.held(nextUpdate)], for: first.string)
            await client.sendUpdate(first.string)
            _ = try await client.queries.wait("obsolete worker drained before the next query") {
                ReadinessQuery.unspentCount(first.string, in: $0) == (fullFallback ? 4 : 3)
            }
            #expect(await account.makeSnapshot().addressBook == before)
            #expect(Self.readyCount(await observations.snapshot()) == readyBefore)
            #expect(await account.loadTransactionHistory().isEmpty)
            #expect(await account.addressBook.listUTXOs().isEmpty)
            nextUpdate.succeed([])
            for address in addresses where address != first { await client.sendUpdate(address.string) }
            _ = try await observations.wait("fresh generation becomes ready") { Self.readyCount($0) > readyBefore }
            #expect(await account.loadTransactionHistory().isEmpty)
            #expect(await account.addressBook.listUTXOs().isEmpty)
        }
    }

    @Test("Manual full history and incremental hydration share the actual book owner")
    func manualHistoryAndIncrementalHydrationShareTheBookOwner() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addresses = await account.listTrackedEntries().map(\.address)
        let address = try #require(await account.listEntries(for: .receiving).first?.address)
        let client = WalletFulcrumReadinessAddressClient()
        let monitor = makeMonitor(account, client: client)
        try await withObservations(monitor) { observations in
            await monitor.start()
            for address in addresses { await client.sendUpdate(address.string) }
            _ = try await observations.wait("initial scope hydrated") { Self.readyCount($0) > 0 }
            let heldHistory = WalletFulcrumReadinessQueryGate<[OpalBase.Network.TransactionHistoryEntry]>()
            let hash = AccountTestFixtures.makeHash(byte: 0xc3)
            let output = OpalBase.Transaction.Output.Unspent(value: 654,
                lockingScript: address.lockingScript.data,
                previousTransactionHash: hash, previousTransactionOutputIndex: 0)
            await client.setHistoryReplies([.held(heldHistory), .value([
                AccountTestFixtures.makeHistoryEntry(hashByte: 0xc3, blockHeight: 200)
            ])], for: address.string)
            await client.setUnspentReplies([.value([output])], for: address.string)
            let manual = Task {
                try await account.refreshTransactionHistory(using: OpalBase.Network.AddressReader(client), usage: .receiving)
            }
            defer {
                heldHistory.fail("manual refresh test cleanup")
                manual.cancel()
            }
            _ = try await client.queries.wait("manual full history holds the owner") {
                ReadinessQuery.historyCount(address.string, in: $0) == 2
            }
            await client.sendUpdate(address.string)
            try await walletFulcrumReadinessBounded("incremental hydration admitted behind full history") {
                while await account.addressBook.chainRefreshCoordinator.queuedOperationCount != 1 {
                    try Task.checkCancellation()
                    await Task.yield()
                }
            }
            #expect(ReadinessQuery.unspentCount(address.string, in: await client.queries.snapshot()) == 1)
            heldHistory.succeed([AccountTestFixtures.makeHistoryEntry(hashByte: 0xc3, blockHeight: 100)])
            _ = try await manual.value
            _ = try await observations.wait("incremental hydration publishes its real UTXO commit") { values in
                values.contains {
                    if case .event(.utxosChanged(let changes)) = $0 { changes.inserted.contains(output) } else { false }
                }
            }
            let record = try #require(await account.loadTransactionHistory().first { $0.transactionHash == hash })
            #expect(record.chainMetadata.height == 200)
            #expect(record.confirmationMetadata.height == 200)
            #expect(await account.addressBook.listUTXOs().contains(output))
            let queries = await client.queries.snapshot()
            #expect(ReadinessQuery.historyCount(address.string, in: queries) == 3)
            #expect(ReadinessQuery.unspentCount(address.string, in: queries) == 2)
        }
    }

    @Test("Canceling queued public work removes its waiter without releasing the active refresh")
    func canceledQueuedPublicRefreshDoesNotReleaseTheActiveOwner() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let address = try #require(await account.listEntries(for: .receiving).first?.address)
        let client = WalletFulcrumReadinessAddressClient()
        let reader = OpalBase.Network.AddressReader(client)
        let heldUTXOs = WalletFulcrumReadinessQueryGate<[OpalBase.Transaction.Output.Unspent]>()
        await client.setUnspentReplies([.held(heldUTXOs), .value([])], for: address.string)
        let active = Task { try await account.refreshUTXOSet(using: reader, usage: .receiving) }
        defer {
            heldUTXOs.fail("queued cancellation test cleanup")
            active.cancel()
        }
        _ = try await client.queries.wait("active public refresh entered its network query") {
            ReadinessQuery.unspentCount(address.string, in: $0) == 1
        }
        let canceled = Task { try await account.refreshTransactionHistory(using: reader, usage: .receiving) }
        defer { canceled.cancel() }
        try await walletFulcrumReadinessBounded("public history refresh is queued") {
            while await account.addressBook.chainRefreshCoordinator.queuedOperationCount != 1 {
                try Task.checkCancellation()
                await Task.yield()
            }
        }
        canceled.cancel()
        do {
            _ = try await walletFulcrumReadinessBounded("queued cancellation completes while owner remains active") {
                try await canceled.value
            }
            Issue.record("Canceled queued public refresh unexpectedly completed")
        } catch is CancellationError {}
        #expect(await account.addressBook.chainRefreshCoordinator.queuedOperationCount == 0)
        #expect(ReadinessQuery.historyCount(address.string, in: await client.queries.snapshot()) == 0)
        let following = Task { try await account.refreshUTXOSet(using: reader, usage: .receiving) }
        defer { following.cancel() }
        try await walletFulcrumReadinessBounded("later public refresh queues behind the same active owner") {
            while await account.addressBook.chainRefreshCoordinator.queuedOperationCount != 1 {
                try Task.checkCancellation()
                await Task.yield()
            }
        }
        #expect(ReadinessQuery.unspentCount(address.string, in: await client.queries.snapshot()) == 1)
        heldUTXOs.succeed([])
        _ = try await walletFulcrumReadinessBounded("active and later public refresh complete") {
            _ = try await active.value
            return try await following.value
        }
        #expect(await account.addressBook.chainRefreshCoordinator.queuedOperationCount == 0)
        #expect(ReadinessQuery.unspentCount(address.string, in: await client.queries.snapshot()) == 2)
        #expect(await account.addressBook.listUTXOs().isEmpty)
    }

    @Test("Successful fallback cannot make an ended subscription ready before reattachment and hydration", arguments: [false, true])
    func endedSubscriptionRequiresReattachmentAndCurrentHydration(reattach: Bool) async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addresses = await account.listTrackedEntries().map(\.address)
        let address = try #require(addresses.first)
        let client = WalletFulcrumReadinessAddressClient()
        let monitor = ReadinessMonitor(account: account, addressReader: .init(client),
            blockHeaderReader: .init(WalletFulcrumReadinessHeaderClient()),
            transactionClient: .init(confirmations: TransactionConfirmationClientTestActor()),
            retryDelay: .milliseconds(1), monitorsBlockHeaders: false)
        let replacement = WalletFulcrumReadinessQueryGate<Void>()
        let hydration = WalletFulcrumReadinessQueryGate<[OpalBase.Transaction.Output.Unspent]>()
        defer {
            replacement.fail("replacement subscription test cleanup")
            hydration.fail("replacement hydration test cleanup")
        }
        let final = try await withObservations(monitor) { observations in
            await monitor.start()
            for address in addresses { await client.sendUpdate(address.string) }
            _ = try await observations.wait("initial subscription scope hydrated") { Self.readyCount($0) > 0 }
            await client.holdSubscription(address.string, using: replacement)
            await client.failSubscription(address.string)
            _ = try await observations.wait("ended subscription's successful full fallback") { values in
                values.contains { if case .event(.performedFullRefresh) = $0 { true } else { false } }
            }
            _ = try await client.queries.wait("replacement subscription attempted after fallback") {
                ReadinessQuery.subscriptionCount(address.string, in: $0) == 2
            }
            if case .synchronized = try await currentState(monitor) {
                Issue.record("Successful data fallback made an ended subscription ready")
            }
            if reattach {
                await client.setUnspentReplies([.held(hydration)], for: address.string)
                replacement.succeed(())
                _ = try await client.queries.wait("replacement subscription is actually attached") { queries in
                    queries.filter { if case .subscriptionReady(let value) = $0 { value == address.string } else { false } }.count == 2
                }
                await client.sendUpdate(address.string)
                _ = try await client.queries.wait("replacement's current snapshot hydration entered") {
                    ReadinessQuery.unspentCount(address.string, in: $0) == 3
                }
                if case .synchronized = try await currentState(monitor) {
                    Issue.record("Replacement became ready before its current snapshot hydrated")
                }
                hydration.succeed([])
                _ = try await observations.wait("replacement's real hydration event completed") { values in
                    values.filter { if case .event(.utxosChanged(let change)) = $0 { change.address == address } else { false } }.count == 2
                }
                _ = try await observations.wait("current replacement scope becomes ready") { Self.lastStateIsReady($0) }
            }
        }
        // Stopping drains the original ordered stream before counting. A transient
        // false-ready during fallback or attachment cannot hide behind its later state.
        #expect(Self.readyCount(final) == (reattach ? 2 : 1))
    }

    @Test("Default header failure survives unrelated successful address hydration")
    func defaultHeaderFailureIsAccountWide() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addresses = await account.listTrackedEntries().map(\.address)
        let first = try #require(addresses.first)
        let client = WalletFulcrumReadinessAddressClient()
        let header = WalletFulcrumReadinessHeaderClient()
        // Intentionally omit monitorsBlockHeaders to protect its production default.
        let monitor = ReadinessMonitor(account: account, addressReader: .init(client),
            blockHeaderReader: .init(header), transactionClient: .init(confirmations: TransactionConfirmationClientTestActor()),
            retryDelay: .seconds(60))
        try await withObservations(monitor) { observations in
            await monitor.start()
            #expect(await header.subscriptionCount == 1)
            for address in addresses { await client.sendUpdate(address.string) }
            _ = try await observations.wait("initial addresses ready") { Self.readyCount($0) > 0 }
            await header.fail()
            _ = try await observations.wait("global header failure") {
                guard let failure = Self.lastFailure($0) else { return false }
                return failure.address == nil
            }
            let readyBefore = Self.readyCount(await observations.snapshot())
            let barrier = WalletFulcrumReadinessQueryGate<[OpalBase.Transaction.Output.Unspent]>()
            await client.setUnspentReplies([.value([]), .held(barrier)], for: first.string)
            await client.sendUpdate(first.string)
            await client.sendUpdate(first.string)
            _ = try await client.queries.wait("address hydration completed after header failure") {
                ReadinessQuery.unspentCount(first.string, in: $0) == 3
            }
            let failure = try #require(Self.lastFailure(await observations.snapshot()))
            #expect(failure.address == nil)
            if case .failed(let currentFailure) = try await currentState(monitor) {
                #expect(currentFailure.address == nil)
            } else {
                Issue.record("Address hydration cleared the default header failure")
            }
            #expect(Self.readyCount(await observations.snapshot()) == readyBefore)
            barrier.succeed([])
        }
    }

    @Test("Canceling one observation keeps monitoring; canceling the last closes subscriptions")
    func observationCancellationOwnsTheStartedMonitor() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addresses = await account.listTrackedEntries().map(\.address)
        let client = WalletFulcrumReadinessAddressClient()
        let monitor = makeMonitor(account, client: client)
        let firstStream = await monitor.makeObservationStream()
        let secondStream = await monitor.makeObservationStream(autoStart: false)
        let observations = ReadinessObservations()
        let first = Task { for try await _ in firstStream {} }
        let second = Task { for try await value in secondStream { await observations.append(value) } }
        do {
            _ = try await client.queries.wait("automatic observation startup subscriptions") { queries in
                addresses.allSatisfy { address in
                    queries.contains { if case .subscriptionReady(let value) = $0 { value == address.string } else { false } }
                }
            }
            first.cancel()
            _ = await first.result
            for address in addresses { await client.sendUpdate(address.string) }
            _ = try await observations.wait("remaining observer receives real hydration") { Self.readyCount($0) > 0 }
            #expect(await client.queries.snapshot().allSatisfy { if case .terminated = $0 { false } else { true } })
            second.cancel()
            _ = await second.result
            _ = try await client.queries.wait("last observer cancels every subscription") { queries in
                addresses.allSatisfy { address in queries.contains { if case .terminated(let value) = $0 { value == address.string } else { false } } }
            }
        } catch {
            first.cancel()
            second.cancel()
            await monitor.stop()
            _ = await first.result
            _ = await second.result
            throw error
        }
        await monitor.stop()
    }

    @Test("Equal successful statuses cause no queries or readiness bounce in the same generation", arguments: [false, true])
    func duplicateSuccessfulStatusSkipsHydration(nullStatus: Bool) async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addresses = await account.listTrackedEntries().map(\.address)
        let first = try #require(addresses.first)
        let status: String? = nullStatus ? nil : "same-status"
        let client = WalletFulcrumReadinessAddressClient()
        let monitor = makeMonitor(account, client: client)
        try await withObservations(monitor) { observations in
            await monitor.start()
            for address in addresses { await client.sendUpdate(address.string, status: status) }
            _ = try await observations.wait("initial hydration is ready") { Self.readyCount($0) == 1 }
            let before = await client.queries.snapshot()
            let beforeEvents = await observations.snapshot().filter { if case .event(.utxosChanged) = $0 { true } else { false } }.count
            let oldPermit = await monitor.eventHub.makeMutationPermit()
            let query = WalletFulcrumReadinessQueryGate<[OpalBase.Network.TransactionHistoryEntry]>()
            await client.setHistoryReplies([.held(query)], for: first.string)
            for _ in 0..<8 { await client.sendUpdate(first.string, status: status) }
            await client.sendUpdate(first.string, status: "ordered-marker", generation: 1)
            _ = try await client.queries.wait("ordered marker's real query is held") {
                ReadinessQuery.historyCount(first.string, in: $0) >= ReadinessQuery.historyCount(first.string, in: before) + 1
            }
            query.succeed([])
            // A new producer generation can be adopted only after earlier same-address
            // inputs finish. This is a read-only epoch barrier, not a test mutation.
            try await walletFulcrumReadinessBounded("same worker admitted marker after all equal inputs") {
                while oldPermit.isCurrent { try Task.checkCancellation(); await Task.yield() }
            }
            _ = try await observations.wait("ordered marker published its real UTXO result") {
                $0.filter { if case .event(.utxosChanged) = $0 { true } else { false } }.count >= beforeEvents + 1
            }
            let after = await client.queries.snapshot()
            #expect(ReadinessQuery.unspentCount(first.string, in: after) == ReadinessQuery.unspentCount(first.string, in: before) + 1)
            #expect(ReadinessQuery.historyCount(first.string, in: after) == ReadinessQuery.historyCount(first.string, in: before) + 1)
            #expect(Self.readyCount(await observations.snapshot()) == 1)
        }
    }

    @Test("Restore data adopts its new producer generation before delayed outage phases", arguments: [false, true])
    func delayedRecoveryPhaseCannotEraseRestoredHydration(nullStatus: Bool) async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addresses = await account.listTrackedEntries().map(\.address)
        let first = try #require(addresses.first)
        let client = WalletFulcrumReadinessAddressClient()
        let states = AsyncStream<OpalBase.Network.Fulcrum.Client.ConnectionRecoveryObservation>.makeStream()
        let monitor = makeMonitor(account, client: client, connectionRecoveryStates: states.stream)
        let status: String? = nullStatus ? nil : "unchanged-restore"
        defer { states.continuation.finish() }
        try await withObservations(monitor) { observations in
            states.continuation.yield(.init(generation: 0, sequence: 0, state: .ready))
            await monitor.start()
            for address in addresses { await client.sendUpdate(address.string, status: status, generation: 0) }
            _ = try await observations.wait("original epoch ready") { Self.readyCount($0) == 1 }
            let oldPermit = await monitor.eventHub.makeMutationPermit()
            // The phase consumer has not received the outage; restore values arrive first.
            for address in addresses { await client.sendUpdate(address.string, status: status, generation: 1) }
            _ = try await client.queries.wait("unchanged restores rehydrate every address") {
                queries in addresses.allSatisfy { ReadinessQuery.historyCount($0.string, in: queries) == 2 }
            }
            // A changed update held in the same address worker proves the restore's final
            // data commit and readiness callback completed before releasing its old phase.
            let next = WalletFulcrumReadinessQueryGate<[OpalBase.Transaction.Output.Unspent]>()
            await client.setUnspentReplies([.held(next)], for: first.string)
            await client.sendUpdate(first.string, status: "drain-barrier", generation: 1)
            _ = try await client.queries.wait("first restored worker completed callbacks") {
                ReadinessQuery.unspentCount(first.string, in: $0) == 3
            }
            #expect(!oldPermit.isCurrent)
            let restoredPermit = await monitor.eventHub.makeMutationPermit()
            states.continuation.yield(.init(generation: 1, sequence: 1, state: .recovering))
            states.continuation.yield(.init(generation: 1, sequence: 2, state: .ready))
            states.continuation.yield(.init(generation: 0, sequence: 0, state: .unavailable))
            next.succeed([])
            _ = try await observations.wait("restored epoch becomes ready despite delayed phases") { Self.readyCount($0) == 2 }
            #expect(restoredPermit.isCurrent)
            let before = await client.queries.snapshot()
            // Buffered older generation data must not mutate or query even with a new value.
            await client.sendUpdate(first.string, status: "old-buffered", generation: 0)
            await client.finishSubscription(first.string)
            _ = try await observations.wait("old buffered data drained") { Self.lastFailure($0)?.message == "Address subscription ended." }
            let after = await client.queries.snapshot()
            #expect(ReadinessQuery.unspentCount(first.string, in: after) == ReadinessQuery.unspentCount(first.string, in: before))
        }
    }

    @Test("An equal status retries after a failed primary hydration even if fallback succeeded", arguments: [false, true])
    func failedPrimaryStatusIsNotDeduplicated(fallbackSucceeds: Bool) async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addresses = await account.listTrackedEntries().map(\.address)
        let first = try #require(addresses.first)
        let client = WalletFulcrumReadinessAddressClient()
        let monitor = makeMonitor(account, client: client)
        try await withObservations(monitor) { observations in
            await monitor.start()
            for address in addresses { await client.sendUpdate(address.string, status: "initial") }
            _ = try await observations.wait("initial scope ready") { Self.readyCount($0) == 1 }
            await client.setUnspentReplies(fallbackSucceeds ? [.failure("primary"), .value([])] : [.failure("primary"), .failure("fallback")], for: first.string)
            await client.sendUpdate(first.string, status: "retry-status")
            _ = try await observations.wait("fallback completed") { values in
                if fallbackSucceeds { return values.contains { if case .event(.performedFullRefresh) = $0 { true } else { false } } }
                return values.filter { if case .event(.encounteredFailure) = $0 { true } else { false } }.count >= 2
            }
            let baseline = ReadinessQuery.unspentCount(first.string, in: await client.queries.snapshot())
            let readyBeforeRetry = Self.readyCount(await observations.snapshot())
            await client.sendUpdate(first.string, status: "retry-status")
            _ = try await observations.wait("equal status really rehydrates") { Self.readyCount($0) > readyBeforeRetry }
            await client.finishSubscription(first.string)
            _ = try await observations.wait("equal retry completed before worker end") { Self.lastFailure($0)?.message == "Address subscription ended." }
            #expect(ReadinessQuery.unspentCount(first.string, in: await client.queries.snapshot()) == baseline + 1)
        }
    }

    @Test("An active cancelled subscription setup retries instead of retaining a completed worker")
    func activeSetupCancellationRetriesAddress() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addresses = await account.listTrackedEntries().map(\.address)
        let first = try #require(addresses.first)
        let client = WalletFulcrumReadinessAddressClient()
        await client.cancelNextSetup(first.string)
        let monitor = makeMonitor(account, client: client, retryDelay: .milliseconds(1))
        try await withObservations(monitor) { observations in
            await monitor.start()
            _ = try await client.queries.wait("cancelled setup restarted and attached") { queries in
                ReadinessQuery.subscriptionCount(first.string, in: queries) == 2 && queries.contains {
                    if case .subscriptionReady(let address) = $0 { address == first.string } else { false }
                }
            }
            for address in addresses { await client.sendUpdate(address.string) }
            _ = try await observations.wait("retried real scope becomes ready") { Self.readyCount($0) > 0 }
            let queries = await client.queries.snapshot()
            #expect(addresses.filter { $0 != first }.allSatisfy { ReadinessQuery.subscriptionCount($0.string, in: queries) == 1 })
        }
    }

    @Test("A live address recovers transient hydration failure without another status notification")
    func failedLiveAddressRetriesWithoutNewStatus() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addresses = await account.listTrackedEntries().map(\.address)
        let first = try #require(addresses.first)
        let client = WalletFulcrumReadinessAddressClient()
        let monitor = makeMonitor(account, client: client, retryDelay: .milliseconds(1))
        try await withObservations(monitor) { observations in
            await monitor.start()
            for address in addresses { await client.sendUpdate(address.string, status: "initial") }
            _ = try await observations.wait("initial scope ready") { Self.readyCount($0) == 1 }
            let baseline = ReadinessQuery.unspentCount(first.string, in: await client.queries.snapshot())
            await client.setUnspentReplies([.failure("transient primary"), .failure("transient fallback"), .value([])], for: first.string)
            await client.sendUpdate(first.string, status: "recovered-status")
            // No further status is emitted until the worker's own failure retry succeeds.
            _ = try await observations.wait("open failed stream rehydrates itself") { Self.readyCount($0) == 2 }
            let queries = await client.queries.snapshot()
            #expect(ReadinessQuery.unspentCount(first.string, in: queries) == baseline + 3)
            #expect(addresses.allSatisfy { ReadinessQuery.subscriptionCount($0.string, in: queries) == 1 })
            let oldPermit = await monitor.eventHub.makeMutationPermit()
            await client.sendUpdate(first.string, status: "recovered-status")
            await client.sendUpdate(first.string, status: "ordered-marker", generation: 1)
            try await walletFulcrumReadinessBounded("duplicate drained before distinct generation marker") {
                while oldPermit.isCurrent { try Task.checkCancellation(); await Task.yield() }
            }
            _ = try await client.queries.wait("marker queried current address") { ReadinessQuery.unspentCount(first.string, in: $0) >= baseline + 4 }
            #expect(ReadinessQuery.unspentCount(first.string, in: await client.queries.snapshot()) == baseline + 4)
        }
    }

    @Test("Ending underlying input fences a held retry's data and ready publication, then a real reattachment recovers", arguments: [false, true])
    func endingInputFencesHeldRetry(throwsOnEnd: Bool) async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addresses = await account.listTrackedEntries().map(\.address)
        let first = try #require(addresses.first)
        let client = WalletFulcrumReadinessAddressClient()
        let monitor = makeMonitor(account, client: client, retryDelay: .milliseconds(1))
        try await withObservations(monitor) { observations in
            await monitor.start()
            for address in addresses { await client.sendUpdate(address.string) }
            _ = try await observations.wait("initial scope ready") { Self.readyCount($0) == 1 }
            let before = ReadinessQuery.unspentCount(first.string, in: await client.queries.snapshot())
            let retry = WalletFulcrumReadinessQueryGate<[OpalBase.Transaction.Output.Unspent]>()
            await client.setUnspentReplies([.failure("primary"), .failure("fallback"), .held(retry)], for: first.string)
            await client.sendUpdate(first.string, status: "retry-status")
            _ = try await client.queries.wait("autonomous retry query held") { ReadinessQuery.unspentCount(first.string, in: $0) == before + 3 }
            if throwsOnEnd { await client.failSubscription(first.string) } else { await client.finishSubscription(first.string) }
            _ = try await observations.wait("underlying owner immediately ended attachment") { Self.lastFailure($0)?.message == "Address subscription ended." }
            let countAtEnd = await observations.snapshot().filter { if case .event(.utxosChanged) = $0 { true } else { false } }.count
            retry.succeed([])
            _ = try await client.queries.wait("old worker completed and genuinely reattached") { ReadinessQuery.subscriptionCount(first.string, in: $0) == 2 }
            #expect(Self.readyCount(await observations.snapshot()) == 1)
            #expect(await observations.snapshot().filter { if case .event(.utxosChanged) = $0 { true } else { false } }.count == countAtEnd)
            await client.sendUpdate(first.string, status: "fresh-attachment")
            _ = try await observations.wait("new attachment's fresh query recovers scope") { Self.readyCount($0) == 2 }
        }
    }

    @Test("Early stamped generation changes preserve every successful scope registration event")
    func earlyGenerationPreservesAddressTrackedRegistration() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addresses = await account.listTrackedEntries().map(\.address)
        let first = try #require(addresses.first)
        let client = WalletFulcrumReadinessAddressClient()
        let gate = WalletFulcrumReadinessQueryGate<Void>()
        await client.holdSubscription(first.string, using: gate)
        let states = AsyncStream<OpalBase.Network.Fulcrum.Client.ConnectionRecoveryObservation>.makeStream()
        let monitor = makeMonitor(account, client: client, connectionRecoveryStates: states.stream)
        defer { states.continuation.finish() }
        try await withObservations(monitor) { observations in
            let start = Task { await monitor.start() }
            do {
                _ = try await client.queries.wait("first registration awaiting setup") { ReadinessQuery.subscriptionCount(first.string, in: $0) == 1 }
                let previous = await monitor.eventHub.makeMutationPermit()
                states.continuation.yield(.init(generation: 1, sequence: 1, state: .recovering))
                try await walletFulcrumReadinessBounded("producer epoch adopted during setup") {
                    while previous.isCurrent { try Task.checkCancellation(); await Task.yield() }
                }
                gate.succeed(())
                await start.value
                states.continuation.yield(.init(generation: 1, sequence: 2, state: .ready))
                for address in addresses { await client.sendUpdate(address.string, status: "restored", generation: 1) }
                _ = try await observations.wait("actual scope ready") { Self.readyCount($0) == 1 }
                let tracked = await observations.snapshot().compactMap { observation -> OpalBase.Address? in
                    if case .event(.addressTracked(let address)) = observation { address } else { nil }
                }
                #expect(Set(tracked) == Set(addresses))
                #expect(tracked.count == addresses.count)
            } catch { gate.fail("cancelled"); start.cancel(); await start.value; throw error }
        }
    }

    @Test("Atomic address admission rejects older producer stamps and returns the exact captured generation permit")
    func atomicAdmissionFencesOlderStamp() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let address = try #require(await account.listTrackedEntries().first?.address)
        let hub = ReadinessMonitor.EventHub(tracksConnectionRecovery: true)
        let identifier = UUID()
        await hub.registerAddress(address)
        await hub.markSubscriptionReady(for: address, identifier: identifier)
        await hub.updateConnectionRecovery(.init(generation: 1, sequence: 1, state: .ready))
        let old = try #require(await hub.prepareAddressUpdate(for: address, subscriptionIdentifier: identifier,
            producerGeneration: 1, matchingSuccessfulPermit: nil))
        await hub.updateConnectionRecovery(.init(generation: 2, sequence: 2, state: .recovering))
        #expect(!old.isCurrent)
        let current = await hub.makeMutationPermit()
        #expect(await hub.prepareAddressUpdate(for: address, subscriptionIdentifier: identifier,
            producerGeneration: 1, matchingSuccessfulPermit: nil) == nil)
        #expect(current.isCurrent)
        let accepted = try #require(await hub.prepareAddressUpdate(for: address, subscriptionIdentifier: identifier,
            producerGeneration: 2, matchingSuccessfulPermit: nil))
        #expect(accepted.isCurrent)
        await hub.markSubscriptionEnded(for: address, identifier: identifier)
        #expect(await hub.prepareAddressUpdate(for: address, subscriptionIdentifier: identifier,
            producerGeneration: 2, matchingSuccessfulPermit: nil) == nil)
    }

    private func makeMonitor(_ account: OpalBase.Account,
                             client: WalletFulcrumReadinessAddressClient,
                             header: WalletFulcrumReadinessHeaderClient = .init(),
                             retryDelay: Duration = .seconds(60),
                             connectionRecoveryStates: AsyncStream<OpalBase.Network.Fulcrum.Client.ConnectionRecoveryObservation>? = nil) -> ReadinessMonitor {
        ReadinessMonitor(account: account, addressReader: .init(client), blockHeaderReader: .init(header),
            transactionClient: .init(confirmations: TransactionConfirmationClientTestActor()), retryDelay: retryDelay,
            monitorsBlockHeaders: false, connectionRecoveryStates: connectionRecoveryStates)
    }

    @discardableResult
    private func withObservations(_ monitor: ReadinessMonitor,
                                  body: (ReadinessObservations) async throws -> Void) async throws -> [ReadinessObservation] {
        let stream = await monitor.makeObservationStream(autoStart: false)
        let observations = ReadinessObservations()
        let collector = Task { for try await observation in stream { await observations.append(observation) } }
        do {
            try await body(observations)
            await monitor.stop()
            try await collector.value
            return await observations.snapshot()
        } catch {
            await monitor.stop()
            collector.cancel()
            _ = await collector.result
            throw error
        }
    }

    private func currentState(_ monitor: ReadinessMonitor) async throws -> ReadinessMonitor.State {
        let stream = await monitor.makeObservationStream(autoStart: false)
        var iterator = stream.makeAsyncIterator()
        guard case .state(let state) = try await iterator.next() else {
            throw WalletFulcrumReadinessTestFailure.forced("Public observer did not receive its current state")
        }
        return state
    }

    private static func readyCount(_ observations: [ReadinessObservation]) -> Int {
        observations.filter { if case .state(.synchronized) = $0 { true } else { false } }.count
    }

    private static func lastFailure(_ observations: [ReadinessObservation]) -> ReadinessMonitor.Failure? {
        for observation in observations.reversed() {
            guard case .state(let state) = observation else { continue }
            if case .failed(let failure) = state { return failure }
            return nil
        }
        return nil
    }

    private static func lastStateIsReady(_ observations: [ReadinessObservation]) -> Bool {
        for observation in observations.reversed() {
            guard case .state(let state) = observation else { continue }
            if case .synchronized = state { return true }
            return false
        }
        return false
    }
}
