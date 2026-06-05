// AccountReadOnlyRuntimeValidator+Refresh.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

extension AccountReadOnlyRuntimeValidator {
    @Test("read-only account refresh and monitor paths run from public descriptors")
    func verifyReadOnlyAccountRunsRefreshAndMonitorPathsFromDescriptors() async throws {
        let privateAccount = try await AccountTestFixtures.makeAccount()
        let readOnlyAccount = try await Self.makeReadOnlyAccount(from: privateAccount)
        let targetAddress = try await readOnlyAccount.selectNextDerivedAddress(for: .receiving)
        let fundingHash = AccountTestFixtures.makeHash(byte: 0x51)
        let unspentOutput = OpalBase.Transaction.Output.Unspent(
            value: 14_000,
            lockingScript: targetAddress.address.lockingScript.data,
            previousTransactionHash: fundingHash,
            previousTransactionOutputIndex: 0
        )
        let addressReader = WalletAddressReaderTestActor(
            balancesByAddress: [
                targetAddress.address.string: .init(confirmed: 14_000, unconfirmed: 0)
            ],
            unspentByAddress: [
                targetAddress.address.string: [unspentOutput]
            ],
            historyByAddress: [
                targetAddress.address.string: [
                    .init(
                        transactionIdentifier: fundingHash.reverseOrder.hexadecimalString,
                        blockHeight: 10,
                        fee: nil
                    )
                ]
            ],
            updatesByAddress: [
                targetAddress.address.string: [
                    .init(kind: .initialSnapshot, address: targetAddress.address.string, status: "ready")
                ]
            ]
        )
        let confirmationClient = TransactionConfirmationClientTestActor(
            statusesByHash: [
                fundingHash: .init(
                    transactionHash: fundingHash,
                    transactionHeight: 12,
                    tipHeight: 15,
                    confirmations: 4
                )
            ]
        )
        let reader = OpalBase.Network.AddressReader(addressReader)
        let expectedBalance = try OpalBase.Satoshi(14_000)

        let utxoRefresh = try await readOnlyAccount.refreshUTXOSet(using: reader, usage: .receiving)
        #expect(utxoRefresh.utxosByAddress[targetAddress.address] == [unspentOutput])
        #expect(utxoRefresh.totalBalance == expectedBalance)

        let historyChangeSet = try await readOnlyAccount.refreshTransactionHistory(
            using: reader,
            usage: .receiving
        )
        #expect(historyChangeSet.inserted.contains { $0.transactionHash == fundingHash })

        let confirmationChangeSet = try await readOnlyAccount.updateTransactionConfirmations(
            using: .init(confirmations: confirmationClient),
            for: [fundingHash]
        )
        #expect(confirmationChangeSet.updated.contains { $0.transactionHash == fundingHash })

        let headerReader = BlockHeaderReaderTestActor(
            snapshots: [.init(height: 15, headerHexadecimal: String(repeating: "a", count: 160))]
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )
        let monitor = await fulcrum.makeMonitor(
            for: readOnlyAccount,
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
            let events = try await WalletFulcrumAddressMonitorSupport.waitForEvents(
                recorder,
                description: "read-only monitor events"
            ) { events in
                WalletFulcrumAddressMonitorSupport.hasAddressTracked(events) &&
                    WalletFulcrumAddressMonitorSupport.hasUTXOChange(events) &&
                    WalletFulcrumAddressMonitorSupport.hasHistoryChange(events)
            }
            #expect(WalletFulcrumAddressMonitorSupport.hasAddressTracked(events))
            #expect(WalletFulcrumAddressMonitorSupport.hasUTXOChange(events))
            #expect(WalletFulcrumAddressMonitorSupport.hasHistoryChange(events))
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
}
