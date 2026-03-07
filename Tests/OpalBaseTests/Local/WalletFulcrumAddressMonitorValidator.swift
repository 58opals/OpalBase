// WalletFulcrumAddressMonitorValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("WalletActor.FulcrumAddressActor.MonitorActor", .tags(.unit, .wallet))
struct WalletFulcrumAddressMonitorValidator {
    @Test("monitor emits tracked, UTXOModel/history, and stopped termination events")
    func monitorEmitsCoreLifecycleEvents() async throws {
        let account = try await AccountTestFixturesModel.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let hash = AccountTestFixturesModel.makeHash(byte: 0x51)
        let unspentOutput = TransactionModel.OutputModel.UnspentModel(
            value: 14_000,
            lockingScript: targetEntry.address.lockingScript.data,
            previousTransactionHash: AccountTestFixturesModel.makeHash(byte: 0x52),
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
        let fulcrum = WalletActor.FulcrumAddressActor(
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
            let initialEvents = try await WalletFulcrumAddressMonitorSupportModel.waitForEvents(recorder, description: "core monitor events") { events in
                WalletFulcrumAddressMonitorSupportModel.hasAddressTracked(events) &&
                    WalletFulcrumAddressMonitorSupportModel.hasUTXOChange(events) &&
                    WalletFulcrumAddressMonitorSupportModel.hasHistoryChange(events)
            }
            #expect(WalletFulcrumAddressMonitorSupportModel.hasAddressTracked(initialEvents))
            #expect(WalletFulcrumAddressMonitorSupportModel.hasUTXOChange(initialEvents))
            #expect(WalletFulcrumAddressMonitorSupportModel.hasHistoryChange(initialEvents))

            await monitor.stop()
            let finalEvents = try await WalletFulcrumAddressMonitorSupportModel.waitForEvents(recorder, description: "stopped termination") { events in
                WalletFulcrumAddressMonitorSupportModel.hasTermination(events, reason: .stopped)
            }
            #expect(WalletFulcrumAddressMonitorSupportModel.hasTermination(finalEvents, reason: .stopped))
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
        let account = try await AccountTestFixturesModel.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let hash = AccountTestFixturesModel.makeHash(byte: 0x58)

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
        let fulcrum = WalletActor.FulcrumAddressActor(
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
            let events = try await WalletFulcrumAddressMonitorSupportModel.waitForEvents(recorder, description: "confirmation changes") { events in
                WalletFulcrumAddressMonitorSupportModel.hasConfirmationChange(events)
            }
            #expect(WalletFulcrumAddressMonitorSupportModel.hasConfirmationChange(events))

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
        let account = try await AccountTestFixturesModel.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let hash = AccountTestFixturesModel.makeHash(byte: 0x61)
        let unspentOutput = TransactionModel.OutputModel.UnspentModel(
            value: 7_000,
            lockingScript: targetEntry.address.lockingScript.data,
            previousTransactionHash: AccountTestFixturesModel.makeHash(byte: 0x62),
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
        let fulcrum = WalletActor.FulcrumAddressActor(
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
            let recoveryEvents = try await WalletFulcrumAddressMonitorSupportModel.waitForEvents(recorder, description: "failure and full refresh") { events in
                WalletFulcrumAddressMonitorSupportModel.hasFailure(events, address: targetEntry.address) &&
                    WalletFulcrumAddressMonitorSupportModel.hasFullRefresh(events)
            }
            #expect(WalletFulcrumAddressMonitorSupportModel.hasFailure(recoveryEvents, address: targetEntry.address))
            #expect(WalletFulcrumAddressMonitorSupportModel.hasFullRefresh(recoveryEvents))

            await monitor.stop(reason: .cancelled)
            let finalEvents = try await WalletFulcrumAddressMonitorSupportModel.waitForEvents(recorder, description: "cancelled termination") { events in
                WalletFulcrumAddressMonitorSupportModel.hasTermination(events, reason: .cancelled)
            }
            #expect(WalletFulcrumAddressMonitorSupportModel.hasTermination(finalEvents, reason: .cancelled))
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

