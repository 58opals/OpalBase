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
}

