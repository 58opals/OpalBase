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

    @Test("retrying non-transport pre-round failure releases reservations")
    func retryingNonTransportPreRoundFailureReleasesReservations() async throws {
        try await assertPreRoundFatalFailureReleasesReservation(
            lastError: .invalidConfiguration,
            diagnostics: .init(
                activity: .retrying,
                retryAttempt: 1,
                nextRetryDelayMilliseconds: 10
            ),
            hashByte: 0xE1
        )
    }

    @Test("retrying pre-round transport failure keeps reservations active")
    func retryingPreRoundTransportFailureKeepsReservationsActive() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 170_000,
            usage: .change,
            hashByte: 0xE0
        )
        let capture = CashFusionWrappedSessionCapture()
        let session = try await makeSession(
            account: account,
            selectedInput: selectedInput,
            capture: capture
        )
        let reservation = await session.reservation
        let fakeSession = try #require(await capture.load())

        await session.start()
        await fakeSession.emit(
            snapshot: .init(
                state: .init(
                    isConnected: false,
                    round: nil
                ),
                lastError: .transportUnavailable,
                lastErrorSummary: "Primary connection failed",
                diagnostics: .init(
                    activity: .retrying,
                    retryAttempt: 1,
                    nextRetryDelayMilliseconds: 10,
                    primaryFailureCategory: .transportUnavailable,
                    primaryFailureSummary: "Primary connection failed"
                )
            )
        )

        #expect(await fakeSession.readStartCount() == 1)
        #expect(await fakeSession.readStopCount() == 0)
        try await assertReceivingEntries(
            reservation.reservedReceivingEntries,
            on: account,
            expectedUsed: true,
            expectedReserved: true
        )
        let addressBook = await account.addressBook
        #expect(await addressBook.listSpendableUTXOs().contains(selectedInput) == false)

        await fakeSession.emit(
            snapshot: .init(
                state: .init(
                    isConnected: true,
                    round: nil
                ),
                diagnostics: .init(activity: .running)
            )
        )

        #expect(await fakeSession.readStopCount() == 0)
        try await assertReceivingEntries(
            reservation.reservedReceivingEntries,
            on: account,
            expectedUsed: true,
            expectedReserved: true
        )

        await fakeSession.emit(
            snapshot: CashFusionTestSupport.makeSnapshot(
                phase: .completed,
                completionStatus: .success,
                diagnostics: .init(activity: .running)
            )
        )

        #expect(await fakeSession.readStopCount() == 1)
        try await assertReceivingEntries(
            reservation.reservedReceivingEntries,
            on: account,
            expectedUsed: true,
            expectedReserved: false
        )
        #expect(await addressBook.listUTXOs().contains(selectedInput) == false)
        #expect(await addressBook.listSpendableUTXOs().contains(selectedInput) == false)
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
        let fakeSession = try #require(await capture.load())

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
        #expect(await addressBook.listUTXOs().contains(selectedInput) == false)
        #expect(await addressBook.listSpendableUTXOs().contains(selectedInput) == false)
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
        let fakeSession = try #require(await capture.load())

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

    @Test("start and explicit stop are idempotent")
    func startAndExplicitStopAreIdempotent() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 170_000,
            usage: .change,
            hashByte: 0xDD
        )
        let capture = CashFusionWrappedSessionCapture()
        let session = try await makeSession(
            account: account,
            selectedInput: selectedInput,
            capture: capture
        )
        let reservation = await session.reservation
        let fakeSession = try #require(await capture.load())

        await session.start()
        await session.start()
        await session.stop()
        await session.stop()

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

    @Test("post-terminal snapshots do not rewrite successful cleanup")
    func postTerminalSnapshotsDoNotRewriteSuccessfulCleanup() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 170_000,
            usage: .change,
            hashByte: 0xDE
        )
        let capture = CashFusionWrappedSessionCapture()
        let session = try await makeSession(
            account: account,
            selectedInput: selectedInput,
            capture: capture
        )
        let reservation = await session.reservation
        let fakeSession = try #require(await capture.load())

        await session.start()
        await fakeSession.emit(
            snapshot: CashFusionTestSupport.makeSnapshot(
                phase: .completed,
                completionStatus: .success
            )
        )
        await session.stop()
        await fakeSession.emit(
            snapshot: .init(
                state: .init(
                    isConnected: false,
                    round: nil
                ),
                lastError: .transportUnavailable
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
        #expect(await addressBook.listUTXOs().contains(selectedInput) == false)
        #expect(await addressBook.listSpendableUTXOs().contains(selectedInput) == false)
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
        let fakeSession = try #require(await capture.load())

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

    @Test("makePublicStatus maps every terminal completion status")
    func makePublicStatusMapsEveryTerminalCompletionStatus() {
        let cases: [(OpalFusion.Round.CompletionStatus, OpalBase.Account.CashFusionSessionStatus.CompletionStatus)] = [
            (.success, .success),
            (.coordinatorRejected, .coordinatorRejected),
            (.hostRejected, .hostRejected),
            (.protocolIncompatible, .protocolIncompatible),
            (.transportFailed, .transportFailed),
            (.blameRequired, .blameRequired)
        ]

        for (fusionStatus, expectedStatus) in cases {
            let publicStatus = OpalBase.Account.CashFusionSessionStatus(
                snapshot: CashFusionTestSupport.makeSnapshot(
                    phase: .completed,
                    completionStatus: fusionStatus
                )
            )

            #expect(publicStatus.round?.completionStatus == expectedStatus)
            #expect(publicStatus.round?.isTerminal == true)
        }
    }

    @Test("makePublicStatus maps every client error category")
    func makePublicStatusMapsEveryClientErrorCategory() {
        let cases: [(OpalFusion.Client.Error, OpalBase.Account.CashFusionSessionStatus.LastError)] = [
            (.invalidConfiguration, .invalidConfiguration),
            (.transportUnavailable, .transportUnavailable),
            (.coordinatorRejected, .coordinatorRejected),
            (.hostRejected, .hostRejected),
            (.protocolIncompatible, .protocolIncompatible),
            (.blameRequired, .blameRequired),
            (.notImplemented, .notImplemented)
        ]

        for (fusionError, expectedError) in cases {
            let publicStatus = OpalBase.Account.CashFusionSessionStatus(
                snapshot: .init(
                    state: .init(),
                    lastError: fusionError,
                    lastErrorSummary: "CashFusion failed"
                )
            )

            #expect(publicStatus.lastError == expectedError)
            #expect(publicStatus.lastErrorSummary == "CashFusion failed")
        }
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
        let fakeSession = try #require(await capture.load())

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
        let fakeSession = try #require(await capture.load())

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
        let fakeSession = try #require(await capture.load())

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
        let fakeSession = try #require(await capture.load())
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

    @Test("makePublicStatus maps retry diagnostics")
    func makePublicStatusMapsRetryDiagnostics() {
        let publicStatus = OpalBase.Account.CashFusionSessionStatus(
            snapshot: .init(
                state: .init(
                    isConnected: false,
                    round: nil
                ),
                lastError: .transportUnavailable,
                lastErrorSummary: "Primary connection failed",
                diagnostics: .init(
                    activity: .retrying,
                    retryAttempt: 2,
                    nextRetryDelayMilliseconds: 4_500,
                    primaryFailureCategory: .transportUnavailable,
                    primaryFailureSummary: "Primary connection failed"
                )
            )
        )

        #expect(publicStatus.isConnected == false)
        #expect(publicStatus.round == nil)
        #expect(publicStatus.lastError == .transportUnavailable)
        #expect(publicStatus.lastErrorSummary == "Primary connection failed")
        #expect(publicStatus.activity == .retrying)
        #expect(publicStatus.retryAttempt == 2)
        #expect(publicStatus.nextRetryDelayMilliseconds == 4_500)
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

    @Test("prepareCashFusionSession forwards production configuration to OpalFusion")
    func prepareCashFusionSessionForwardsProductionConfigurationToOpalFusion() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 170_000,
            usage: .change,
            hashByte: 0xDF
        )
        let genesisHash = (0..<32).map(UInt8.init)
        let configuration = OpalBase.Account.CashFusionSession.Configuration(
            coordinator: .init(
                host: "cashfusion.example.com",
                port: 8788,
                requiresTLS: true
            ),
            covertChannel: .init(
                entryPath: "/fusion/covert",
                maxPayloadBytes: 64 * 1_024,
                requestTimeoutMilliseconds: 12_345
            ),
            torSocks5: .init(
                host: "127.0.0.1",
                port: 9150,
                resolvesCoordinatorHostNameRemotely: false
            ),
            genesisHash: genesisHash,
            joinPools: .init(
                tiers: [100_000, 1_000_000],
                tags: [
                    .init(
                        identifier: [0x01, 0x02, 0x03, 0x04],
                        limit: 2,
                        noIp: true
                    ),
                    .init(
                        identifier: [0x05, 0x06, 0x07, 0x08],
                        limit: 1,
                        noIp: false
                    )
                ]
            )
        )
        let capture = CashFusionWrappedSessionCapture()
        let session = try await makeSession(
            account: account,
            selectedInput: selectedInput,
            configuration: configuration,
            capture: capture
        )
        let clientConfiguration = try #require(await capture.loadConfiguration())
        let torSocks5 = try #require(clientConfiguration.torSocks5)
        let joinPools = try #require(await capture.loadJoinPools())
        let reconnectPolicy = try #require(await capture.loadReconnectPolicy())

        #expect(clientConfiguration.coordinatorHost == configuration.coordinator.host)
        #expect(clientConfiguration.coordinatorPort == configuration.coordinator.port)
        #expect(clientConfiguration.coordinatorRequiresTLS)
        #expect(clientConfiguration.covertChannel.entryPath == configuration.covertChannel.entryPath)
        #expect(clientConfiguration.covertChannel.maxPayloadBytes == configuration.covertChannel.maxPayloadBytes)
        #expect(
            clientConfiguration.covertChannel.requestTimeoutMilliseconds ==
                configuration.covertChannel.requestTimeoutMilliseconds
        )
        #expect(torSocks5.host == configuration.torSocks5?.host)
        #expect(torSocks5.port == configuration.torSocks5?.port)
        #expect(
            torSocks5.resolvesCoordinatorHostNameRemotely ==
                configuration.torSocks5?.resolvesCoordinatorHostNameRemotely
        )
        #expect(await capture.loadGenesisHash() == configuration.genesisHash)
        #expect(joinPools.tiers == configuration.joinPools.tiers)
        #expect(joinPools.tags.map(\.identifier) == configuration.joinPools.tags.map(\.identifier))
        #expect(joinPools.tags.map(\.limit) == configuration.joinPools.tags.map(\.limit))
        #expect(joinPools.tags.map(\.noIp) == configuration.joinPools.tags.map(\.noIp))
        #expect(reconnectPolicy == .walletDefault)

        await session.stop()
    }
}

private extension AccountCashFusionSessionValidator {
    func assertPreRoundFatalFailureReleasesReservation(
        lastError: OpalFusion.Client.Error,
        diagnostics: OpalFusion.Client.Diagnostics = .init(),
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
        let fakeSession = try #require(await capture.load())

        await session.start()
        await fakeSession.emit(
            snapshot: .init(
                state: .init(
                    isConnected: false,
                    round: nil
                ),
                lastError: lastError,
                diagnostics: diagnostics
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
            sessionFactory: {
                clientConfiguration,
                genesisHash,
                joinPools,
                _,
                _,
                _,
                wrappedStateObserver,
                reconnectPolicy in
                let session = CashFusionFakeWrappedSession(
                    stateObserver: wrappedStateObserver
                )
                await capture.store(
                    session,
                    configuration: clientConfiguration,
                    genesisHash: genesisHash,
                    joinPools: joinPools,
                    reconnectPolicy: reconnectPolicy
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
        let clientConfiguration = try #require(await capture.loadConfiguration())

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
