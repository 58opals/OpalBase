import Foundation
import Testing
@testable import OpalBase

@Suite("Wallet.FulcrumAddress.Monitor", .tags(.unit, .wallet))
struct WalletFulcrumAddressMonitorValidator {
    @Test("monitor emits tracked, UTXO/history, and stopped termination events")
    func monitorEmitsCoreLifecycleEvents() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let hash = AccountTestFixtures.makeHash(byte: 0x51)
        let unspentOutput = Transaction.Output.Unspent(
            value: 14_000,
            lockingScript: targetEntry.address.lockingScript.data,
            previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x52),
            previousTransactionOutputIndex: 0
        )

        let addressReader = WalletAddressReaderStub(
            unspentByAddress: [targetEntry.address.string: [unspentOutput]],
            historyByAddress: [
                targetEntry.address.string: [.init(transactionIdentifier: hash.reverseOrder.hexadecimalString, blockHeight: 10, fee: nil)]
            ],
            updatesByAddress: [
                targetEntry.address.string: [.init(kind: .initialSnapshot, address: targetEntry.address.string, status: "ready")]
            ]
        )
        let confirmationClient = TransactionConfirmationClientStub(
            statusesByHash: [hash: .init(transactionHash: hash, transactionHeight: 12, tipHeight: 15, confirmations: 4)]
        )
        let headerReader = BlockHeaderReaderStub(
            snapshots: [.init(height: 15, headerHexadecimal: String(repeating: "a", count: 160))]
        )
        let fulcrum = Wallet.FulcrumAddress(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )
        let monitor = await fulcrum.makeMonitor(
            for: account,
            blockHeaderReader: headerReader,
            retryDelay: .milliseconds(10)
        )
        let stream = await monitor.makeEventStream(autoStart: true)
        let recorder = MonitorEventRecorder()
        let collector = Task {
            do {
                for try await event in stream {
                    await recorder.append(event)
                }
            } catch { }
        }
        do {
            let initialEvents = try await waitForEvents(recorder, description: "core monitor events") { events in
                hasAddressTracked(events) &&
                    hasUTXOChange(events) &&
                    hasHistoryChange(events)
            }
            #expect(hasAddressTracked(initialEvents))
            #expect(hasUTXOChange(initialEvents))
            #expect(hasHistoryChange(initialEvents))

            await monitor.stop()
            let finalEvents = try await waitForEvents(recorder, description: "stopped termination") { events in
                hasTermination(events, reason: .stopped)
            }
            #expect(hasTermination(finalEvents, reason: .stopped))
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

        let addressReader = WalletAddressReaderStub(
            historyByAddress: [
                targetEntry.address.string: [.init(transactionIdentifier: hash.reverseOrder.hexadecimalString, blockHeight: 10, fee: nil)]
            ]
        )
        _ = try await account.refreshTransactionHistory(
            for: targetEntry.address,
            using: addressReader,
            includeUnconfirmed: true
        )

        let confirmationClient = TransactionConfirmationClientStub(
            statusesByHash: [hash: .init(transactionHash: hash, transactionHeight: 12, tipHeight: 20, confirmations: 9)]
        )
        let headerReader = BlockHeaderReaderStub(
            snapshots: [.init(height: 20, headerHexadecimal: String(repeating: "b", count: 160))]
        )
        let fulcrum = Wallet.FulcrumAddress(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )
        let monitor = await fulcrum.makeMonitor(
            for: account,
            blockHeaderReader: headerReader,
            retryDelay: .milliseconds(10)
        )
        let stream = await monitor.makeEventStream(autoStart: true)
        let recorder = MonitorEventRecorder()
        let collector = Task {
            do {
                for try await event in stream {
                    await recorder.append(event)
                }
            } catch { }
        }
        do {
            let events = try await waitForEvents(recorder, description: "confirmation changes") { events in
                hasConfirmationChange(events)
            }
            #expect(hasConfirmationChange(events))

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
        let unspentOutput = Transaction.Output.Unspent(
            value: 7_000,
            lockingScript: targetEntry.address.lockingScript.data,
            previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x62),
            previousTransactionOutputIndex: 0
        )

        let addressReader = WalletAddressReaderStub(
            unspentByAddress: [targetEntry.address.string: [unspentOutput]],
            historyByAddress: [
                targetEntry.address.string: [.init(transactionIdentifier: hash.reverseOrder.hexadecimalString, blockHeight: 5, fee: nil)]
            ],
            updatesByAddress: [
                targetEntry.address.string: [.init(kind: .initialSnapshot, address: targetEntry.address.string, status: "update")]
            ],
            failUnspentCountByAddress: [targetEntry.address.string: 1]
        )
        let confirmationClient = TransactionConfirmationClientStub()
        let headerReader = BlockHeaderReaderStub(snapshots: .init())
        let fulcrum = Wallet.FulcrumAddress(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )
        let monitor = await fulcrum.makeMonitor(
            for: account,
            blockHeaderReader: headerReader,
            retryDelay: .milliseconds(10)
        )
        let stream = await monitor.makeEventStream(autoStart: true)
        let recorder = MonitorEventRecorder()
        let collector = Task {
            do {
                for try await event in stream {
                    await recorder.append(event)
                }
            } catch { }
        }
        do {
            let recoveryEvents = try await waitForEvents(recorder, description: "failure and full refresh") { events in
                hasFailure(events, address: targetEntry.address) &&
                    hasFullRefresh(events)
            }
            #expect(hasFailure(recoveryEvents, address: targetEntry.address))
            #expect(hasFullRefresh(recoveryEvents))

            await monitor.stop(reason: .cancelled)
            let finalEvents = try await waitForEvents(recorder, description: "cancelled termination") { events in
                hasTermination(events, reason: .cancelled)
            }
            #expect(hasTermination(finalEvents, reason: .cancelled))
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

private actor MonitorEventRecorder {
    private var events: [Wallet.FulcrumAddress.Monitor.Event] = .init()

    func append(_ event: Wallet.FulcrumAddress.Monitor.Event) {
        events.append(event)
    }

    func snapshot() -> [Wallet.FulcrumAddress.Monitor.Event] {
        events
    }
}

private enum MonitorTestError: Swift.Error {
    case timedOut(String)
}

private func waitForEvents(
    _ recorder: MonitorEventRecorder,
    description: String,
    timeout: Duration = .seconds(8),
    condition: ([Wallet.FulcrumAddress.Monitor.Event]) -> Bool
) async throws -> [Wallet.FulcrumAddress.Monitor.Event] {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        let events = await recorder.snapshot()
        if condition(events) {
            return events
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw MonitorTestError.timedOut(description)
}

private func hasAddressTracked(_ events: [Wallet.FulcrumAddress.Monitor.Event]) -> Bool {
    events.contains { if case .addressTracked = $0 { true } else { false } }
}

private func hasUTXOChange(_ events: [Wallet.FulcrumAddress.Monitor.Event]) -> Bool {
    events.contains { if case .utxosChanged = $0 { true } else { false } }
}

private func hasHistoryChange(_ events: [Wallet.FulcrumAddress.Monitor.Event]) -> Bool {
    events.contains { if case .historyChanged = $0 { true } else { false } }
}

private func hasConfirmationChange(_ events: [Wallet.FulcrumAddress.Monitor.Event]) -> Bool {
    events.contains { if case .confirmationsChanged = $0 { true } else { false } }
}

private func hasFullRefresh(_ events: [Wallet.FulcrumAddress.Monitor.Event]) -> Bool {
    events.contains { if case .performedFullRefresh = $0 { true } else { false } }
}

private func hasFailure(
    _ events: [Wallet.FulcrumAddress.Monitor.Event],
    address: Address
) -> Bool {
    events.contains {
        guard case .encounteredFailure(let failure) = $0 else { return false }
        return failure.address == address
    }
}

private func hasTermination(
    _ events: [Wallet.FulcrumAddress.Monitor.Event],
    reason: Wallet.FulcrumAddress.Monitor.Termination.Reason
) -> Bool {
    events.contains {
        guard case .terminated(let termination) = $0 else { return false }
        return termination.reason == reason
    }
}
