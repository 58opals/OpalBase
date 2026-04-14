#if os(macOS)
// AccountCashFusionSessionValidator.swift

import Foundation
import OpalFusion
import Testing
@testable import OpalBase

@Suite("OpalBase.Account CashFusion session", .tags(.unit, .wallet))
struct AccountCashFusionSessionValidator {
    @Test("invalid configuration releases reservations before a round starts")
    func invalidConfigurationReleasesReservationsBeforeARoundStarts() async throws {
        try await assertPreRoundFatalFailureReleasesReservation(
            lastError: .invalidConfiguration,
            hashByte: 0xD5
        )
    }

    @Test("transport failure releases reservations before a round starts")
    func transportFailureReleasesReservationsBeforeARoundStarts() async throws {
        try await assertPreRoundFatalFailureReleasesReservation(
            lastError: .transportUnavailable,
            hashByte: 0xD6
        )
    }

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
                completionStatus: .success
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
                completionStatus: nil
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

    @Test("makePublicStatus maps a disconnected snapshot with no round")
    func makePublicStatusMapsADisconnectedSnapshotWithNoRound() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 170_000,
            usage: .change,
            hashByte: 0xD7
        )
        let capture = CashFusionWrappedSessionCapture()
        let session = try await makeSession(
            account: account,
            selectedInput: selectedInput,
            capture: capture
        )

        let publicStatus = await session.makePublicStatus()

        #expect(
            publicStatus == .init(
                isConnected: false,
                round: nil,
                lastError: nil,
                lastErrorSummary: nil
            )
        )

        await session.stop()
    }

    @Test("makePublicStatus keeps nil error summary for idle snapshots")
    func makePublicStatusKeepsNilErrorSummaryForIdleSnapshots() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 170_000,
            usage: .change,
            hashByte: 0xDB
        )
        let capture = CashFusionWrappedSessionCapture()
        let session = try await makeSession(
            account: account,
            selectedInput: selectedInput,
            capture: capture
        )
        let fakeSession = try #require(capture.load())

        await fakeSession.emit(
            snapshot: CashFusionTestSupport.makeSnapshot(
                identifier: "round-idle",
                phase: .idle,
                isConnected: false
            )
        )

        let publicStatus = await session.makePublicStatus()

        #expect(publicStatus.isConnected == false)
        #expect(publicStatus.round?.identifier == "round-idle")
        #expect(publicStatus.round?.phase == .idle)
        #expect(publicStatus.lastError == nil)
        #expect(publicStatus.lastErrorSummary == nil)

        await session.stop()
    }

    @Test("makePublicStatus maps an active round snapshot")
    func makePublicStatusMapsAnActiveRoundSnapshot() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 170_000,
            usage: .change,
            hashByte: 0xD8
        )
        let capture = CashFusionWrappedSessionCapture()
        let session = try await makeSession(
            account: account,
            selectedInput: selectedInput,
            capture: capture
        )
        let fakeSession = try #require(capture.load())

        await fakeSession.emit(
            snapshot: CashFusionTestSupport.makeSnapshot(
                identifier: "round-active",
                phase: .assemblingTransaction,
                isConnected: true
            )
        )

        let publicStatus = await session.makePublicStatus()

        #expect(publicStatus.isConnected)
        #expect(
            publicStatus.round == .init(
                identifier: "round-active",
                phase: .assemblingTransaction,
                participantCount: 3,
                completionStatus: nil,
                isTerminal: false
            )
        )
        #expect(publicStatus.lastError == nil)
        #expect(publicStatus.lastErrorSummary == nil)

        await session.stop()
    }

    @Test("makePublicStatus maps terminal success snapshots")
    func makePublicStatusMapsTerminalSuccessSnapshots() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 170_000,
            usage: .change,
            hashByte: 0xD9
        )
        let capture = CashFusionWrappedSessionCapture()
        let session = try await makeSession(
            account: account,
            selectedInput: selectedInput,
            capture: capture
        )
        let fakeSession = try #require(capture.load())

        await fakeSession.emit(
            snapshot: CashFusionTestSupport.makeSnapshot(
                identifier: "round-success",
                phase: .completed,
                completionStatus: .success,
                isConnected: true
            )
        )

        let publicStatus = await session.makePublicStatus()

        #expect(publicStatus.isConnected)
        #expect(
            publicStatus.round == .init(
                identifier: "round-success",
                phase: .completed,
                participantCount: 3,
                completionStatus: .success,
                isTerminal: true
            )
        )
        #expect(publicStatus.lastError == nil)
        #expect(publicStatus.lastErrorSummary == nil)

        await session.stop()
    }

    @Test("makePublicStatus preserves last error values and summary")
    func makePublicStatusPreservesLastErrorValuesAndSummary() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 170_000,
            usage: .change,
            hashByte: 0xDA
        )
        let capture = CashFusionWrappedSessionCapture()
        let session = try await makeSession(
            account: account,
            selectedInput: selectedInput,
            capture: capture
        )
        let fakeSession = try #require(capture.load())
        let lastErrorSummary = "Primary connect failed: connection reset"

        await fakeSession.emit(
            snapshot: .init(
                state: .init(
                    isConnected: false,
                    round: nil
                ),
                lastError: .transportUnavailable,
                lastErrorSummary: lastErrorSummary
            )
        )

        let publicStatus = await session.makePublicStatus()

        #expect(publicStatus.isConnected == false)
        #expect(publicStatus.round == nil)
        #expect(publicStatus.lastError == .transportUnavailable)
        #expect(publicStatus.lastErrorSummary == lastErrorSummary)

        await session.stop()
    }

    @Test("prepareCashFusionSession maps coordinator TLS into wrapped client configuration")
    func prepareCashFusionSessionMapsCoordinatorTLSIntoWrappedClientConfiguration() async throws {
        try await assertWrappedClientConfiguration(
            requiresTLS: false,
            hashByte: 0xDB
        )
        try await assertWrappedClientConfiguration(
            requiresTLS: true,
            hashByte: 0xDC
        )
    }
}

private extension AccountCashFusionSessionValidator {
    func assertPreRoundFatalFailureReleasesReservation(
        lastError: OpalFusion.Client.Error,
        hashByte: UInt8
    ) async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 170_000,
            usage: .change,
            hashByte: hashByte
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
            snapshot: .init(
                state: .init(
                    isConnected: false,
                    round: nil
                ),
                lastError: lastError
            )
        )

        #expect(await fakeSession.readStartCount() == 1)
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

    func makeSession(
        account: OpalBase.Account,
        selectedInput: OpalBase.Transaction.Output.Unspent,
        configuration: OpalBase.Account.CashFusionSession.Configuration = CashFusionTestSupport.makeConfiguration(),
        capture: CashFusionWrappedSessionCapture
    ) async throws -> OpalBase.Account.CashFusionSession {
        try await account.prepareCashFusionSession(
            configuration: configuration,
            request: .init(
                selectedInputs: [selectedInput],
                outputAmounts: [try OpalBase.Satoshi(55_000)]
            ),
            sessionFactory: { clientConfiguration, _, _, _, _, _, wrappedStateObserver in
                let session = CashFusionFakeWrappedSession(
                    stateObserver: wrappedStateObserver
                )
                capture.store(
                    session,
                    configuration: clientConfiguration
                )
                return session
            }
        )
    }

    func assertWrappedClientConfiguration(
        requiresTLS: Bool,
        hashByte: UInt8
    ) async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 170_000,
            usage: .change,
            hashByte: hashByte
        )
        let configuration = CashFusionTestSupport.makeConfiguration(
            requiresTLS: requiresTLS
        )
        let capture = CashFusionWrappedSessionCapture()
        let session = try await makeSession(
            account: account,
            selectedInput: selectedInput,
            configuration: configuration,
            capture: capture
        )
        let clientConfiguration = try #require(capture.loadConfiguration())

        #expect(clientConfiguration.coordinatorHost == configuration.coordinator.host)
        #expect(clientConfiguration.coordinatorPort == configuration.coordinator.port)
        #expect(clientConfiguration.coordinatorRequiresTLS == requiresTLS)

        await session.stop()
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
#endif
