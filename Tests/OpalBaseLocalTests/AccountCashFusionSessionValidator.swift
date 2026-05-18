// AccountCashFusionSessionValidator.swift

#if os(macOS)
import Foundation
import OpalDiagnostics
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

    @Test("non-transport pre-round failure releases reservations")
    func nonTransportPreRoundFailureReleasesReservations() async throws {
        try await assertPreRoundFatalFailureReleasesReservation(
            lastError: .invalidConfiguration,
            hashByte: 0xE1
        )
    }

    @Test("pre-round transport failure keeps reservations active while reconnect is enabled")
    func preRoundTransportFailureKeepsReservationsActiveWhileReconnectIsEnabled() async throws {
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
                lastErrorSummary: "Primary connection failed"
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
                )
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
                completionStatus: .success
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

    @Test("snapshot preserves the session trace identifier")
    func snapshotPreservesTheSessionTraceIdentifier() async throws {
        let traceID = OpalDiagnostics.TraceID()
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 170_000,
            usage: .change,
            hashByte: 0xD9
        )
        let capture = CashFusionWrappedSessionCapture()
        let session = try await OpalDiagnostics.withTraceID(traceID) {
            try await makeSession(
                account: account,
                selectedInput: selectedInput,
                capture: capture
            )
        }
        let fakeSession = try #require(await capture.load())

        _ = await session.snapshot()

        #expect(await fakeSession.readSnapshotTraceIDs() == [traceID])
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

    @Test("host rejection cancels dynamic round reservations")
    func hostRejectionCancelsDynamicRoundReservations() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 150_000,
            usage: .change,
            hashByte: 0xE2
        )
        let capture = CashFusionWrappedSessionCapture()
        let session = try await makeSession(
            account: account,
            selectedInput: selectedInput,
            outputPolicy: .valuePreserving,
            capture: capture
        )
        let reservation = await session.reservation
        let fakeSession = try #require(await capture.load())
        let participantReservationSource = try #require(
            await capture.loadParticipantReservationSource()
        )
        let context = OpalFusion.Host.ParticipantReservationContext(
            roundIdentifier: .init(rawValue: "round-host-rejected"),
            tierSatoshis: 100_000,
            numberOfComponents: 2,
            componentFeeRateSatoshisPerKb: 1_000,
            minimumExcessFeeSatoshis: 200,
            maximumExcessFeeSatoshis: 500
        )

        _ = try await participantReservationSource.participantReservation(for: context)
        let roundReservation = try await reservation.roundReservation(for: context.roundIdentifier)

        await session.start()
        await fakeSession.emit(
            snapshot: CashFusionTestSupport.makeSnapshot(
                identifier: context.roundIdentifier.rawValue,
                phase: .completed,
                completionStatus: .hostRejected
            )
        )

        #expect(await fakeSession.readStartCount() == 1)
        #expect(await fakeSession.readStopCount() == 1)
        try await assertReceivingEntries(
            roundReservation.reservedReceivingEntries,
            on: account,
            expectedUsed: false,
            expectedReserved: false
        )
        let addressBook = await account.addressBook
        #expect(await addressBook.listSpendableUTXOs().contains(selectedInput))
    }

    @Test("failed terminal snapshots record error diagnostics")
    func failedTerminalSnapshotsRecordErrorDiagnostics() async throws {
        let records = try await OpalDiagnostics.withConfiguration(cashFusionDiagnosticsConfiguration()) {
            let account = try await AccountTestFixtures.makeAccount()
            let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
                to: account,
                value: 150_000,
                usage: .change,
                hashByte: 0xE3
            )
            let capture = CashFusionWrappedSessionCapture()
            let session = try await makeSession(
                account: account,
                selectedInput: selectedInput,
                capture: capture
            )
            let fakeSession = try #require(await capture.load())

            await session.start()
            await fakeSession.emit(
                snapshot: CashFusionTestSupport.makeSnapshot(
                    phase: .completed,
                    completionStatus: .hostRejected
                )
            )

            return OpalDiagnostics.recentRecords
        }

        let failedFinalRecord = try #require(records.last { record in
            record.event == OpalDiagnostics.Event.cashFusionSessionFinalized &&
                record.fields.contains {
                    $0.name == OpalDiagnostics.Field.Name.outcome &&
                        $0.value == "failed"
                }
        })
        #expect(failedFinalRecord.level == .error)
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

    @Test("makePublicStatus exposes recorded local outputs for successful completed rounds")
    func makePublicStatusExposesRecordedLocalOutputsForSuccessfulCompletedRounds() async throws {
        let roundIdentifier = "round-completed-output"
        let fixture = try await makeSessionWithRecordedCompletedOutput(
            roundIdentifier: roundIdentifier,
            hashByte: 0xE3
        )
        let recordedOutput = try #require(fixture.completedLocalOutputs.first)

        await fixture.fakeSession.emit(
            snapshot: CashFusionTestSupport.makeSnapshot(
                identifier: roundIdentifier,
                phase: .completed,
                completionStatus: .success,
                isConnected: true
            )
        )

        let publicStatus = await fixture.session.makePublicStatus()

        #expect(publicStatus.round?.completionStatus == .success)
        #expect(publicStatus.completedLocalOutputs == [recordedOutput])
    }
    
    @Test("makePublicStatus preserves terminal success after wrapped snapshot resets")
    func makePublicStatusPreservesTerminalSuccessAfterWrappedSnapshotResets() async throws {
        let roundIdentifier = "round-success-reset-output"
        let fixture = try await makeSessionWithRecordedCompletedOutput(
            roundIdentifier: roundIdentifier,
            hashByte: 0xE8
        )
        let recordedOutput = try #require(fixture.completedLocalOutputs.first)
        
        await fixture.fakeSession.emit(
            snapshot: CashFusionTestSupport.makeSnapshot(
                identifier: roundIdentifier,
                phase: .completed,
                completionStatus: .success,
                isConnected: true
            )
        )
        await fixture.fakeSession.emit(
            snapshot: .init(
                state: .init(
                    isConnected: false,
                    round: nil
                )
            )
        )
        
        let publicStatus = await fixture.session.makePublicStatus()
        
        #expect(publicStatus.round?.identifier == roundIdentifier)
        #expect(publicStatus.round?.completionStatus == .success)
        #expect(publicStatus.completedLocalOutputs == [recordedOutput])
    }

    @Test("makePublicStatus hides recorded local outputs for non-success statuses")
    func makePublicStatusHidesRecordedLocalOutputsForNonSuccessStatuses() async throws {
        let rejectedRoundIdentifier = "round-rejected-output"
        let rejectedFixture = try await makeSessionWithRecordedCompletedOutput(
            roundIdentifier: rejectedRoundIdentifier,
            hashByte: 0xE4
        )

        await rejectedFixture.fakeSession.emit(
            snapshot: CashFusionTestSupport.makeSnapshot(
                identifier: rejectedRoundIdentifier,
                phase: .completed,
                completionStatus: .hostRejected,
                isConnected: true
            )
        )

        let rejectedPublicStatus = await rejectedFixture.session.makePublicStatus()
        #expect(rejectedPublicStatus.completedLocalOutputs.isEmpty)

        let stoppedFixture = try await makeSessionWithRecordedCompletedOutput(
            roundIdentifier: "round-stopped-output",
            hashByte: 0xE5
        )

        await stoppedFixture.session.stop()

        let stoppedPublicStatus = await stoppedFixture.session.makePublicStatus()
        #expect(stoppedPublicStatus.completedLocalOutputs.isEmpty)

        let retryingFixture = try await makeSessionWithRecordedCompletedOutput(
            roundIdentifier: "round-retrying-output",
            hashByte: 0xE6
        )

        await retryingFixture.fakeSession.emit(
            snapshot: .init(
                state: .init(
                    isConnected: false,
                    round: nil
                ),
                lastError: .transportUnavailable
            )
        )

        let retryingPublicStatus = await retryingFixture.session.makePublicStatus()
        #expect(retryingPublicStatus.completedLocalOutputs.isEmpty)
        await retryingFixture.session.stop()

        let activeRoundIdentifier = "round-active-output"
        let activeFixture = try await makeSessionWithRecordedCompletedOutput(
            roundIdentifier: activeRoundIdentifier,
            hashByte: 0xE7
        )

        await activeFixture.fakeSession.emit(
            snapshot: CashFusionTestSupport.makeSnapshot(
                identifier: activeRoundIdentifier,
                phase: .assemblingTransaction,
                completionStatus: nil,
                isConnected: true
            )
        )

        let activePublicStatus = await activeFixture.session.makePublicStatus()
        #expect(activePublicStatus.completedLocalOutputs.isEmpty)
        await activeFixture.session.stop()
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

    @Test("makePublicStatus maps failure activity without retry diagnostics")
    func makePublicStatusMapsFailureActivityWithoutRetryDiagnostics() {
        let publicStatus = OpalBase.Account.CashFusionSessionStatus(
            snapshot: .init(
                state: .init(
                    isConnected: false,
                    round: nil
                ),
                lastError: .transportUnavailable,
                lastErrorSummary: "Primary connection failed"
            )
        )

        #expect(publicStatus.isConnected == false)
        #expect(publicStatus.round == nil)
        #expect(publicStatus.lastError == .transportUnavailable)
        #expect(publicStatus.lastErrorSummary == "Primary connection failed")
        #expect(publicStatus.activity == .failed)
        #expect(publicStatus.retryAttempt == nil)
        #expect(publicStatus.nextRetryDelayMilliseconds == nil)
    }

    @Test("makePublicStatus maps coordinator queue status")
    func makePublicStatusMapsCoordinatorQueueStatus() {
        let publicStatus = OpalBase.Account.CashFusionSessionStatus(
            snapshot: CashFusionTestSupport.makeSnapshot(
                phase: .connecting,
                coordinatorStatus: .init(
                    updateSequence: 7,
                    latestInboundMessageKind: "TierStatusUpdate",
                    latestInboundPayloadByteCount: 24,
                    queueStatus: .init(
                        tierSatoshis: 100_000,
                        players: 3,
                        minPlayers: 2,
                        maxPlayers: 8,
                        timeRemaining: 17
                    )
                )
            )
        )

        #expect(
            publicStatus.coordinatorStatus == .init(
                updateSequence: 7,
                latestMessageKind: "TierStatusUpdate",
                latestMessagePayloadByteCount: 24,
                queueStatus: .init(
                    tierSatoshis: 100_000,
                    playerCount: 3,
                    minimumPlayerCount: 2,
                    maximumPlayerCount: 8,
                    timeRemainingSeconds: 17
                )
            )
        )
    }

    @Test("makePublicStatus maps empty coordinator status")
    func makePublicStatusMapsEmptyCoordinatorStatus() {
        let publicStatus = OpalBase.Account.CashFusionSessionStatus(
            snapshot: .init()
        )

        #expect(publicStatus.coordinatorStatus == .init())
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
    func cashFusionDiagnosticsConfiguration() -> OpalDiagnostics.Configuration {
        OpalDiagnostics.Configuration(
            minimumLevel: .debug,
            categoryFilter: .all,
            bufferPolicy: .enabled(capacity: 128)
        )
    }

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
        let fakeSession = try #require(await capture.load())

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
        outputPolicy: OpalBase.Account.CashFusionRequest.OutputPolicy? = nil,
        configuration: OpalBase.Account.CashFusionSession.Configuration = CashFusionTestSupport.makeConfiguration(),
        capture: CashFusionWrappedSessionCapture
    ) async throws -> OpalBase.Account.CashFusionSession {
        let resolvedOutputPolicy = try outputPolicy ?? .explicitAmounts([OpalBase.Satoshi(55_000)])

        return try await account.prepareCashFusionSession(
            configuration: configuration,
            request: .init(
                selectedInputs: [selectedInput],
                outputPolicy: resolvedOutputPolicy
            ),
            sessionFactory: {
                clientConfiguration,
                genesisHash,
                joinPools,
                participantReservationSource,
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
                    participantReservationSource: participantReservationSource,
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

    func makeSessionWithRecordedCompletedOutput(
        roundIdentifier: String,
        hashByte: UInt8
    ) async throws -> (
        session: OpalBase.Account.CashFusionSession,
        fakeSession: CashFusionFakeWrappedSession,
        completedLocalOutputs: [OpalBase.Transaction.Output.Unspent]
    ) {
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
        let completedLocalOutputs = try await recordCompletedLocalOutputs(
            roundIdentifier: .init(rawValue: roundIdentifier),
            in: reservation,
            value: 55_000
        )

        return (session, fakeSession, completedLocalOutputs)
    }

    func recordCompletedLocalOutputs(
        roundIdentifier: OpalFusion.Round.Identifier,
        in reservation: OpalBase.Account.CashFusionReservation,
        value: UInt64
    ) async throws -> [OpalBase.Transaction.Output.Unspent] {
        _ = try await reservation.participantReservation(for: roundIdentifier)
        let selectedInput = try #require(reservation.selectedInputs.first)
        let localOutput = try makeLocalOutput(for: reservation, value: value)
        let finalizedTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: selectedInput.previousTransactionHash,
                    previousTransactionOutputIndex: selectedInput.previousTransactionOutputIndex,
                    unlockingScript: Data()
                )
            ],
            outputs: [localOutput],
            lockTime: 0
        )
        let finalizedTransactionBytes = try finalizedTransaction.encode()
        let finalizedTransactionHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(finalizedTransactionBytes)
        )

        try await reservation.recordCompletedLocalOutputs(
            for: roundIdentifier,
            finalizedTransaction: finalizedTransaction,
            finalizedTransactionHash: finalizedTransactionHash
        )

        return await reservation.completedLocalOutputs(for: roundIdentifier)
    }

    func makeLocalOutput(
        for reservation: OpalBase.Account.CashFusionReservation,
        value: UInt64
    ) throws -> OpalBase.Transaction.Output {
        let receivingEntry = try #require(reservation.reservedReceivingEntries.first)
        return OpalBase.Transaction.Output(
            value: value,
            lockingScript: receivingEntry.address.lockingScript.data
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
#endif
