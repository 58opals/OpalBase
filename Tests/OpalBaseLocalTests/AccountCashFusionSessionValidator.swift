// AccountCashFusionSessionValidator.swift

import Foundation
import OpalFusion
import Testing
@testable import OpalBase

@Suite("OpalBase.Account CashFusion session", .tags(.unit, .wallet))
struct AccountCashFusionSessionValidator {
    @Test("successful terminal snapshot completes reservations")
    func successfulTerminalSnapshotCompletesReservations() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 170_000,
            usage: .change,
            hashByte: 0xD1
        )
        let capture = CashFusionWrappedSessionCapture()
        let session = try await makeSession(
            account: account,
            selectedInput: selectedInput,
            capture: capture
        )
        let reservation = await session.reservation
        let fakeSession = try #require(capture.load())

        await session.start()
        await fakeSession.emit(
            snapshot: CashFusionTestSupport.makeSnapshot(
                phase: .completed,
                completionStatus: .success,
                isTerminal: true
            )
        )

        #expect(await fakeSession.readStartCount() == 1)
        #expect(await fakeSession.readStopCount() == 1)
        try await assertReceivingEntries(
            reservation.reservedReceivingEntries,
            on: account,
            expectedUsed: true,
            expectedReserved: false
        )
        let addressBook = await account.addressBook
        #expect(await addressBook.listSpendableUTXOs().contains(selectedInput))
    }

    @Test("explicit stop cancels reservations")
    func explicitStopCancelsReservations() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 170_000,
            usage: .change,
            hashByte: 0xD2
        )
        let capture = CashFusionWrappedSessionCapture()
        let session = try await makeSession(
            account: account,
            selectedInput: selectedInput,
            capture: capture
        )
        let reservation = await session.reservation
        let fakeSession = try #require(capture.load())

        await session.stop()

        #expect(await fakeSession.readStopCount() == 1)
        try await assertReceivingEntries(
            reservation.reservedReceivingEntries,
            on: account,
            expectedUsed: false,
            expectedReserved: false
        )
        let addressBook = await account.addressBook
        #expect(await addressBook.listSpendableUTXOs().contains(selectedInput))
    }

    @Test("restart and blame intermediate snapshots keep reservations active")
    func restartAndBlameIntermediateSnapshotsKeepReservationsActive() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 170_000,
            usage: .change,
            hashByte: 0xD3
        )
        let capture = CashFusionWrappedSessionCapture()
        let session = try await makeSession(
            account: account,
            selectedInput: selectedInput,
            capture: capture
        )
        let reservation = await session.reservation
        let fakeSession = try #require(capture.load())

        await session.start()
        await fakeSession.emit(
            snapshot: CashFusionTestSupport.makeSnapshot(
                phase: .blame,
                completionStatus: nil,
                isTerminal: false
            )
        )

        #expect(await fakeSession.readStopCount() == 0)
        try await assertReceivingEntries(
            reservation.reservedReceivingEntries,
            on: account,
            expectedUsed: true,
            expectedReserved: true
        )
        let addressBook = await account.addressBook
        #expect(await addressBook.listSpendableUTXOs().contains(selectedInput) == false)

        await session.stop()
    }

    @Test("caller observers receive forwarded state and event updates")
    func callerObserversReceiveForwardedStateAndEventUpdates() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 170_000,
            usage: .change,
            hashByte: 0xD4
        )
        let capture = CashFusionWrappedSessionCapture()
        let stateObserver = CashFusionStateObserverSpy()
        let eventObserver = CashFusionEventObserverSpy()
        let session = try await makeSession(
            account: account,
            selectedInput: selectedInput,
            capture: capture,
            eventObserver: eventObserver,
            stateObserver: stateObserver
        )
        let fakeSession = try #require(capture.load())
        let expectedSnapshot = CashFusionTestSupport.makeSnapshot(
            phase: .assemblingTransaction
        )
        let expectedEvent = OpalFusion.Host.Event(
            kind: .status,
            phase: .assemblingTransaction,
            summary: "assembling transaction",
            isTerminal: false
        )
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "round-forwarded")

        await session.start()
        await fakeSession.emit(snapshot: expectedSnapshot)
        await fakeSession.emit(event: expectedEvent, for: roundIdentifier)

        #expect(await stateObserver.snapshotHistory().contains(expectedSnapshot))
        #expect(
            await eventObserver.recordHistory().contains(
                .init(event: expectedEvent, roundIdentifier: roundIdentifier)
            )
        )

        await session.stop()
    }
}

private extension AccountCashFusionSessionValidator {
    func makeSession(
        account: OpalBase.Account,
        selectedInput: OpalBase.Transaction.Output.Unspent,
        capture: CashFusionWrappedSessionCapture,
        eventObserver: (any OpalFusion.Host.EventObserver)? = nil,
        stateObserver: (any OpalFusion.Client.StateObserver)? = nil
    ) async throws -> OpalBase.Account.CashFusionSession {
        try await account.prepareCashFusionSession(
            configuration: CashFusionTestSupport.makeConfiguration(),
            joinPools: CashFusionTestSupport.makeJoinPools(),
            request: .init(
                selectedInputs: [selectedInput],
                outputAmounts: [try OpalBase.Satoshi(55_000)]
            ),
            eventObserver: eventObserver,
            stateObserver: stateObserver,
            sessionFactory: { _, _, _, _, _, wrappedEventObserver, wrappedStateObserver in
                let session = CashFusionFakeWrappedSession(
                    eventObserver: wrappedEventObserver,
                    stateObserver: wrappedStateObserver
                )
                capture.store(session)
                return session
            }
        )
    }

    func assertReceivingEntries(
        _ entries: [OpalBase.Address.Book.Entry],
        on account: OpalBase.Account,
        expectedUsed: Bool,
        expectedReserved: Bool
    ) async throws {
        let receivingEntries = await account.listEntries(for: .receiving)

        for reservedEntry in entries {
            let refreshedEntry = try #require(
                receivingEntries.first(where: { $0.address == reservedEntry.address })
            )
            #expect(refreshedEntry.isUsed == expectedUsed)
            #expect(refreshedEntry.isReserved == expectedReserved)
        }
    }
}
