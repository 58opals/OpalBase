// OpalBase+Account+CashFusionSession.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    public actor CashFusionSession {
        enum TerminalOutcome: Sendable, Equatable {
            case success
            case stopped
            case failed
        }

        let reservation: CashFusionReservation
        let wrappedSession: any CashFusionWrappedSession
        let observerSink: CashFusionObserverSink
        let traceID: OpalBase.Diagnostics.TraceID

        var hasStarted = false
        var hasStoppedWrappedSession = false
        var terminalOutcome: TerminalOutcome?
        var successfulTerminalSnapshot: OpalFusion.Client.Session.Snapshot?

        init(
            reservation: CashFusionReservation,
            wrappedSession: any CashFusionWrappedSession,
            observerSink: CashFusionObserverSink,
            traceID: OpalBase.Diagnostics.TraceID
        ) {
            self.reservation = reservation
            self.wrappedSession = wrappedSession
            self.observerSink = observerSink
            self.traceID = traceID
        }

        public func start() async {
            await OpalBase.Diagnostics.withTraceID(traceID) {
                guard terminalOutcome == nil, hasStarted == false else {
                    return
                }

                hasStarted = true
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.cashFusionSessionStarted,
                    category: OpalBase.Diagnostics.Categories.cashFusion,
                    fields: [
                        OpalBaseDiagnostics.operationField("cash_fusion_session_start"),
                        OpalBaseDiagnostics.moduleField()
                    ]
                )
                await wrappedSession.start()
            }
        }

        public func stop() async {
            await finalize(with: .stopped)
        }

        func snapshot() async -> OpalFusion.Client.Session.Snapshot {
            await wrappedSession.snapshot()
        }

        func receiveCashFusionSnapshot(
            _ snapshot: OpalFusion.Client.Session.Snapshot
        ) async {
            guard terminalOutcome == nil else {
                return
            }

            if snapshot.lastError != nil,
               snapshot.state.round == nil,
               isRetryingPreRoundTransportFailure(snapshot) == false {
                await finalize(with: .failed)
                return
            }

            guard let round = snapshot.state.round,
                  round.isTerminal || round.completionStatus != nil else {
                return
            }

            switch round.completionStatus {
            case .success?:
                successfulTerminalSnapshot = snapshot
                await finalize(with: .success)
            case .none:
                await finalize(with: .failed)
            default:
                await finalize(with: .failed)
            }
        }

        private func isRetryingPreRoundTransportFailure(
            _ snapshot: OpalFusion.Client.Session.Snapshot
        ) -> Bool {
            snapshot.lastError == .transportUnavailable &&
                snapshot.diagnostics.activity == .retrying
        }

        private func finalize(with outcome: TerminalOutcome) async {
            await OpalBase.Diagnostics.withTraceID(traceID) {
                guard terminalOutcome == nil else {
                    return
                }

                terminalOutcome = outcome
                await observerSink.unbind()
                await stopWrappedSessionIfNeeded()

                do {
                    switch outcome {
                    case .success:
                        try await reservation.complete()
                    case .stopped, .failed:
                        try await reservation.cancel()
                    }
                    OpalBaseDiagnostics.record(
                        OpalBase.Diagnostics.Events.cashFusionSessionFinalized,
                        category: OpalBase.Diagnostics.Categories.cashFusion,
                        fields: [
                            OpalBaseDiagnostics.operationField("cash_fusion_session_finalize"),
                            OpalBaseDiagnostics.moduleField(),
                            OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.outcome, outcome.diagnosticsName)
                        ]
                    )
                } catch {
                    OpalBaseDiagnostics.record(
                        OpalBase.Diagnostics.Events.cashFusionSessionFinalized,
                        category: OpalBase.Diagnostics.Categories.cashFusion,
                        level: .error,
                        fields: [
                            OpalBaseDiagnostics.operationField("cash_fusion_session_finalize"),
                            OpalBaseDiagnostics.moduleField(),
                            OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.outcome, outcome.diagnosticsName)
                        ] + OpalBaseDiagnostics.errorFields(
                            for: error,
                            fallback: OpalBase.Diagnostics.ErrorCodes.cashFusionSessionFailed
                        )
                    )
                    assertionFailure("CashFusion reservation cleanup failed: \(error)")
                }
            }
        }

        private func stopWrappedSessionIfNeeded() async {
            guard hasStoppedWrappedSession == false else {
                return
            }

            hasStoppedWrappedSession = true
            await wrappedSession.stop()
        }
    }
}

private extension _OpalBase.Account.CashFusionSession.TerminalOutcome {
    var diagnosticsName: String {
        switch self {
        case .success:
            return "success"
        case .stopped:
            return "stopped"
        case .failed:
            return "failed"
        }
    }
}
#endif
