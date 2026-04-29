// WalletFulcrumAddressMonitorValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Wallet.Fulcrum.Monitor", .tags(.unit, .wallet))
struct WalletFulcrumAddressMonitorValidator {
    @Test("monitor emits tracked, UTXO/history, and stopped termination events")
    func monitorEmitsCoreLifecycleEvents() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let hash = AccountTestFixtures.makeHash(byte: 0x51)
        let unspentOutput = OpalBase.Transaction.Output.Unspent(
            value: 14_000,
            lockingScript: targetEntry.address.lockingScript.data,
            previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x52),
            previousTransactionOutputIndex: 0
        )

        let addressReader = WalletAddressReaderTestActor(
            unspentByAddress: [targetEntry.address.string: [unspentOutput]],
            historyByAddress: [
                targetEntry.address.string: [.init(transactionIdentifier: hash.reverseOrder.hexadecimalString, blockHeight: 10, fee: nil)]
            ],
            updatesByAddress: [
                targetEntry.address.string: [.init(kind: .initialSnapshot, address: targetEntry.address.string, status: "ready")]
            ]
        )
        let confirmationClient = TransactionConfirmationClientTestActor(
            statusesByHash: [hash: .init(transactionHash: hash, transactionHeight: 12, tipHeight: 15, confirmations: 4)]
        )
        let headerReader = BlockHeaderReaderTestActor(
            snapshots: [.init(height: 15, headerHexadecimal: String(repeating: "a", count: 160))]
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )
        let monitor = await fulcrum.makeMonitor(
            for: account,
            blockHeaderReader: headerReader,
            retryDelay: .milliseconds(10)
        )
        let stream = await monitor.makeEventStream(autoStart: true)
        let recorder = WalletFulcrumAddressMonitorEventRecorderActor()
        let collector = Task {
            do {
                for try await event in stream {
                    await recorder.append(event)
                }
            } catch { }
        }
        do {
            let initialEvents = try await WalletFulcrumAddressMonitorSupport.waitForEvents(recorder, description: "core monitor events") { events in
                WalletFulcrumAddressMonitorSupport.hasAddressTracked(events) &&
                    WalletFulcrumAddressMonitorSupport.hasUTXOChange(events) &&
                    WalletFulcrumAddressMonitorSupport.hasHistoryChange(events)
            }
            #expect(WalletFulcrumAddressMonitorSupport.hasAddressTracked(initialEvents))
            #expect(WalletFulcrumAddressMonitorSupport.hasUTXOChange(initialEvents))
            #expect(WalletFulcrumAddressMonitorSupport.hasHistoryChange(initialEvents))

            await monitor.stop()
            let finalEvents = try await WalletFulcrumAddressMonitorSupport.waitForEvents(recorder, description: "stopped termination") { events in
                WalletFulcrumAddressMonitorSupport.hasTermination(events, reason: .stopped)
            }
            #expect(WalletFulcrumAddressMonitorSupport.hasTermination(finalEvents, reason: .stopped))
        } catch {
            await monitor.stop(reason: .cancelled)
            collector.cancel()
            _ = await collector.result
            throw error
        }
        collector.cancel()
        _ = await collector.result
    }

    @Test("monitor publishes matching history before UTXO changes")
    func monitorPublishesMatchingHistoryBeforeUTXOChanges() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let fundingHash = AccountTestFixtures.makeHash(byte: 0x81)
        let unspentOutput = OpalBase.Transaction.Output.Unspent(
            value: 12_000,
            lockingScript: targetEntry.address.lockingScript.data,
            previousTransactionHash: fundingHash,
            previousTransactionOutputIndex: 0
        )

        let addressReader = WalletAddressReaderTestActor(
            unspentByAddress: [targetEntry.address.string: [unspentOutput]],
            historyByAddress: [
                targetEntry.address.string: [.init(transactionIdentifier: fundingHash.reverseOrder.hexadecimalString, blockHeight: 14, fee: nil)]
            ],
            updatesByAddress: [
                targetEntry.address.string: [.init(kind: .initialSnapshot, address: targetEntry.address.string, status: "ready")]
            ]
        )
        let confirmationClient = TransactionConfirmationClientTestActor()
        let headerReader = BlockHeaderReaderTestActor(snapshots: .init())
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )
        let monitor = await fulcrum.makeMonitor(
            for: account,
            blockHeaderReader: headerReader,
            retryDelay: .milliseconds(10)
        )
        let stream = await monitor.makeEventStream(autoStart: true)
        let recorder = WalletFulcrumAddressMonitorEventRecorderActor()
        let collector = Task {
            do {
                for try await event in stream {
                    await recorder.append(event)
                }
            } catch { }
        }
        do {
            let events = try await WalletFulcrumAddressMonitorSupport.waitForEvents(recorder, description: "matching history before UTXO") { events in
                WalletFulcrumAddressMonitorSupport.firstHistoryChangeIndex(events, containing: fundingHash) != nil &&
                    WalletFulcrumAddressMonitorSupport.firstUTXOChangeIndex(events, containing: unspentOutput) != nil
            }
            let historyIndex = try #require(WalletFulcrumAddressMonitorSupport.firstHistoryChangeIndex(events, containing: fundingHash))
            let utxoIndex = try #require(WalletFulcrumAddressMonitorSupport.firstUTXOChangeIndex(events, containing: unspentOutput))
            #expect(historyIndex < utxoIndex)

            let records = await account.loadTransactionHistory()
            #expect(records.contains { $0.transactionHash == fundingHash })

            await monitor.stop()
        } catch {
            await monitor.stop(reason: .cancelled)
            collector.cancel()
            _ = await collector.result
            throw error
        }
        collector.cancel()
        _ = await collector.result
    }

    @Test("monitor falls back without partial UTXO event when history refresh fails")
    func monitorFallsBackWithoutPartialUTXOEventWhenHistoryRefreshFails() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let fundingHash = AccountTestFixtures.makeHash(byte: 0x82)
        let unspentOutput = OpalBase.Transaction.Output.Unspent(
            value: 11_000,
            lockingScript: targetEntry.address.lockingScript.data,
            previousTransactionHash: fundingHash,
            previousTransactionOutputIndex: 0
        )

        let addressReader = WalletAddressReaderTestActor(
            unspentByAddress: [targetEntry.address.string: [unspentOutput]],
            historyByAddress: [
                targetEntry.address.string: [.init(transactionIdentifier: fundingHash.reverseOrder.hexadecimalString, blockHeight: 15, fee: nil)]
            ],
            updatesByAddress: [
                targetEntry.address.string: [.init(kind: .initialSnapshot, address: targetEntry.address.string, status: "update")]
            ],
            failHistoryCountByAddress: [targetEntry.address.string: 1]
        )
        let confirmationClient = TransactionConfirmationClientTestActor()
        let headerReader = BlockHeaderReaderTestActor(snapshots: .init())
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )
        let monitor = await fulcrum.makeMonitor(
            for: account,
            blockHeaderReader: headerReader,
            retryDelay: .milliseconds(10)
        )
        let stream = await monitor.makeEventStream(autoStart: true)
        let recorder = WalletFulcrumAddressMonitorEventRecorderActor()
        let collector = Task {
            do {
                for try await event in stream {
                    await recorder.append(event)
                }
            } catch { }
        }
        do {
            let recoveryEvents = try await WalletFulcrumAddressMonitorSupport.waitForEvents(recorder, description: "history failure full refresh") { events in
                WalletFulcrumAddressMonitorSupport.hasFailure(events, address: targetEntry.address) &&
                    WalletFulcrumAddressMonitorSupport.hasFullRefresh(events)
            }
            #expect(WalletFulcrumAddressMonitorSupport.firstUTXOChangeIndex(recoveryEvents) == nil)

            let historyRequests = await addressReader.readHistoryRequests()
            #expect(historyRequests.count >= 2)

            await monitor.stop(reason: .cancelled)
        } catch {
            await monitor.stop(reason: .cancelled)
            collector.cancel()
            _ = await collector.result
            throw error
        }
        collector.cancel()
        _ = await collector.result
    }

    @Test("monitor emits confirmation changes when block headers advance")
    func monitorEmitsConfirmationChanges() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let hash = AccountTestFixtures.makeHash(byte: 0x58)

        let addressReader = WalletAddressReaderTestActor(
            historyByAddress: [
                targetEntry.address.string: [.init(transactionIdentifier: hash.reverseOrder.hexadecimalString, blockHeight: 10, fee: nil)]
            ]
        )
        _ = try await account.refreshTransactionHistory(
            for: targetEntry.address,
            using: addressReader,
            includeUnconfirmed: true
        )

        let confirmationClient = TransactionConfirmationClientTestActor(
            statusesByHash: [hash: .init(transactionHash: hash, transactionHeight: 12, tipHeight: 20, confirmations: 9)]
        )
        let headerReader = BlockHeaderReaderTestActor(
            snapshots: [.init(height: 20, headerHexadecimal: String(repeating: "b", count: 160))]
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )
        let monitor = await fulcrum.makeMonitor(
            for: account,
            blockHeaderReader: headerReader,
            retryDelay: .milliseconds(10)
        )
        let stream = await monitor.makeEventStream(autoStart: true)
        let recorder = WalletFulcrumAddressMonitorEventRecorderActor()
        let collector = Task {
            do {
                for try await event in stream {
                    await recorder.append(event)
                }
            } catch { }
        }
        do {
            let events = try await WalletFulcrumAddressMonitorSupport.waitForEvents(recorder, description: "confirmation changes") { events in
                WalletFulcrumAddressMonitorSupport.hasConfirmationChange(events)
            }
            #expect(WalletFulcrumAddressMonitorSupport.hasConfirmationChange(events))

            await monitor.stop()
        } catch {
            await monitor.stop(reason: .cancelled)
            collector.cancel()
            _ = await collector.result
            throw error
        }
        collector.cancel()
        _ = await collector.result
    }

    @Test("monitor emits failure, performs full refresh recovery, and reports cancelled termination")
    func monitorEmitsFailureAndRecoveryEvents() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let hash = AccountTestFixtures.makeHash(byte: 0x61)
        let unspentOutput = OpalBase.Transaction.Output.Unspent(
            value: 7_000,
            lockingScript: targetEntry.address.lockingScript.data,
            previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x62),
            previousTransactionOutputIndex: 0
        )

        let addressReader = WalletAddressReaderTestActor(
            unspentByAddress: [targetEntry.address.string: [unspentOutput]],
            historyByAddress: [
                targetEntry.address.string: [.init(transactionIdentifier: hash.reverseOrder.hexadecimalString, blockHeight: 5, fee: nil)]
            ],
            updatesByAddress: [
                targetEntry.address.string: [.init(kind: .initialSnapshot, address: targetEntry.address.string, status: "update")]
            ],
            failUnspentCountByAddress: [targetEntry.address.string: 1]
        )
        let confirmationClient = TransactionConfirmationClientTestActor()
        let headerReader = BlockHeaderReaderTestActor(snapshots: .init())
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )
        let monitor = await fulcrum.makeMonitor(
            for: account,
            blockHeaderReader: headerReader,
            retryDelay: .milliseconds(10)
        )
        let stream = await monitor.makeEventStream(autoStart: true)
        let recorder = WalletFulcrumAddressMonitorEventRecorderActor()
        let collector = Task {
            do {
                for try await event in stream {
                    await recorder.append(event)
                }
            } catch { }
        }
        do {
            let recoveryEvents = try await WalletFulcrumAddressMonitorSupport.waitForEvents(recorder, description: "failure and full refresh") { events in
                WalletFulcrumAddressMonitorSupport.hasFailure(events, address: targetEntry.address) &&
                    WalletFulcrumAddressMonitorSupport.hasFullRefresh(events)
            }
            #expect(WalletFulcrumAddressMonitorSupport.hasFailure(recoveryEvents, address: targetEntry.address))
            #expect(WalletFulcrumAddressMonitorSupport.hasFullRefresh(recoveryEvents))

            await monitor.stop(reason: .cancelled)
            let finalEvents = try await WalletFulcrumAddressMonitorSupport.waitForEvents(recorder, description: "cancelled termination") { events in
                WalletFulcrumAddressMonitorSupport.hasTermination(events, reason: .cancelled)
            }
            #expect(WalletFulcrumAddressMonitorSupport.hasTermination(finalEvents, reason: .cancelled))
        } catch {
            await monitor.stop(reason: .cancelled)
            collector.cancel()
            _ = await collector.result
            throw error
        }
        collector.cancel()
        _ = await collector.result
    }

    @Test("convenience event stream retains its monitor until core events arrive")
    func convenienceEventStreamRetainsMonitorUntilCoreEventsArrive() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let hash = AccountTestFixtures.makeHash(byte: 0x71)
        let unspentOutput = OpalBase.Transaction.Output.Unspent(
            value: 15_000,
            lockingScript: targetEntry.address.lockingScript.data,
            previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x72),
            previousTransactionOutputIndex: 0
        )

        let addressReader = WalletAddressReaderTestActor(
            unspentByAddress: [targetEntry.address.string: [unspentOutput]],
            historyByAddress: [
                targetEntry.address.string: [.init(transactionIdentifier: hash.reverseOrder.hexadecimalString, blockHeight: 11, fee: nil)]
            ],
            updatesByAddress: [
                targetEntry.address.string: [.init(kind: .initialSnapshot, address: targetEntry.address.string, status: "ready")]
            ]
        )
        let confirmationClient = TransactionConfirmationClientTestActor(
            statusesByHash: [hash: .init(transactionHash: hash, transactionHeight: 13, tipHeight: 16, confirmations: 4)]
        )
        let headerReader = BlockHeaderReaderTestActor(
            snapshots: [.init(height: 16, headerHexadecimal: String(repeating: "d", count: 160))]
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )

        let stream = await fulcrum.makeEventStream(
            for: account,
            blockHeaderReader: headerReader,
            retryDelay: .milliseconds(10)
        )
        let recorder = WalletFulcrumAddressMonitorEventRecorderActor()
        let collector = Task {
            do {
                for try await event in stream {
                    await recorder.append(event)
                }
            } catch { }
        }
        do {
            let events = try await WalletFulcrumAddressMonitorSupport.waitForEvents(recorder, description: "convenience monitor core events") { events in
                WalletFulcrumAddressMonitorSupport.hasAddressTracked(events) &&
                    WalletFulcrumAddressMonitorSupport.hasUTXOChange(events) &&
                    WalletFulcrumAddressMonitorSupport.hasHistoryChange(events)
            }

            #expect(WalletFulcrumAddressMonitorSupport.hasAddressTracked(events))
            #expect(WalletFulcrumAddressMonitorSupport.hasUTXOChange(events))
            #expect(WalletFulcrumAddressMonitorSupport.hasHistoryChange(events))
        } catch {
            collector.cancel()
            _ = await collector.result
            throw error
        }
        collector.cancel()
        _ = await collector.result
    }

    @Test("convenience event stream cancels subscriptions when the collector ends")
    func convenienceEventStreamCancelsSubscriptionsWhenCollectorEnds() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let addressReader = WalletAddressReaderTestActor(
            updatesByAddress: [
                targetEntry.address.string: [.init(kind: .initialSnapshot, address: targetEntry.address.string, status: "ready")]
            ]
        )
        let confirmationClient = TransactionConfirmationClientTestActor()
        let headerReader = BlockHeaderReaderTestActor(
            snapshots: [.init(height: 21, headerHexadecimal: String(repeating: "e", count: 160))]
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )

        let stream = await fulcrum.makeEventStream(
            for: account,
            blockHeaderReader: headerReader,
            retryDelay: .milliseconds(10)
        )
        let collector = Task {
            do {
                for try await _ in stream { }
            } catch { }
        }
        await Task.yield()
        do {
            try await WalletFulcrumAddressMonitorSupport.waitUntil(
                description: "convenience monitor subscriptions started",
                timeout: .seconds(20)
            ) {
                let subscribeRequests = await addressReader.readSubscribeRequests()
                let subscriptionCount = await headerReader.readSubscriptionCount()
                return !subscribeRequests.isEmpty && subscriptionCount > 0
            }

            collector.cancel()
            _ = await collector.result

            try await WalletFulcrumAddressMonitorSupport.waitUntil(
                description: "convenience monitor subscriptions terminated",
                timeout: .seconds(20)
            ) {
                let addressTerminations = await addressReader.readSubscriptionTerminationCount(for: targetEntry.address.string)
                let tipTerminations = await headerReader.readTerminationCount()
                return addressTerminations > 0 && tipTerminations > 0
            }
        } catch {
            collector.cancel()
            _ = await collector.result
            throw error
        }
    }

    @Test("monitor deinit cancels address and header subscriptions without explicit stop")
    func monitorDeinitCancelsSubscriptions() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let addressReader = WalletAddressReaderTestActor(
            updatesByAddress: [
                targetEntry.address.string: [.init(kind: .initialSnapshot, address: targetEntry.address.string, status: "ready")]
            ]
        )
        let confirmationClient = TransactionConfirmationClientTestActor()
        let headerReader = BlockHeaderReaderTestActor(
            snapshots: [.init(height: 15, headerHexadecimal: String(repeating: "c", count: 160))]
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )

        weak var weakMonitor: OpalBase.Wallet.Fulcrum.Monitor?
        var strongMonitor: OpalBase.Wallet.Fulcrum.Monitor? = await fulcrum.makeMonitor(
            for: account,
            blockHeaderReader: headerReader,
            retryDelay: .milliseconds(10)
        )
        weakMonitor = strongMonitor

        if let monitor = strongMonitor {
            await monitor.start()

            try await WalletFulcrumAddressMonitorSupport.waitUntil(description: "monitor tasks started") {
                let addressSubscriptionCount = await monitor.addressSubscriptions.count
                let hasHeaderTask = await monitor.headerTask != nil
                return addressSubscriptionCount > 0 && hasHeaderTask
            }
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!(await addressReader.readSubscribeRequests()).isEmpty)
        #expect(await headerReader.readSubscriptionCount() > 0)

        strongMonitor = nil

        for _ in 0..<100 {
            if weakMonitor == nil {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(weakMonitor == nil)

        try await WalletFulcrumAddressMonitorSupport.waitUntil(description: "subscription termination") {
            let addressTerminations = await addressReader.readSubscriptionTerminationCount(for: targetEntry.address.string)
            let tipTerminations = await headerReader.readTerminationCount()
            return addressTerminations > 0 && tipTerminations > 0
        }
    }
}
