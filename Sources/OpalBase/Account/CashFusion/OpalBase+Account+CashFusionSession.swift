// OpalBase+Account+CashFusionSession.swift

#if os(macOS)
import Foundation
import OpalDiagnostics
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
        let traceID: OpalDiagnostics.TraceID
        let reconnectPolicy: OpalFusion.Client.ReconnectPolicy

        var hasStarted = false
        var hasStoppedWrappedSession = false
        var terminalOutcome: TerminalOutcome?
        var successfulTerminalSnapshot: OpalFusion.Client.Session.Snapshot?
        var preRoundTransportFailureRetryAttempt = 0

        init(
            reservation: CashFusionReservation,
            wrappedSession: any CashFusionWrappedSession,
            observerSink: CashFusionObserverSink,
            traceID: OpalDiagnostics.TraceID,
            reconnectPolicy: OpalFusion.Client.ReconnectPolicy
        ) {
            self.reservation = reservation
            self.wrappedSession = wrappedSession
            self.observerSink = observerSink
            self.traceID = traceID
            self.reconnectPolicy = reconnectPolicy
        }

        public func start() async {
            await OpalDiagnostics.withTraceID(traceID) {
                guard terminalOutcome == nil, hasStarted == false else {
                    return
                }

                hasStarted = true
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.cashFusionSessionStarted,
                    category: OpalDiagnostics.Category.cashFusion,
                    fields: [
                        OpalDiagnostics.Field.operation("cash_fusion_session_start"),
                        OpalDiagnostics.Field.module()
                    ]
                )
                await wrappedSession.start()
            }
        }

        public func stop() async {
            await finalize(with: .stopped)
        }

        func snapshot() async -> OpalFusion.Client.Session.Snapshot {
            await OpalDiagnostics.withTraceID(traceID) {
                await wrappedSession.snapshot()
            }
        }

        func receiveCashFusionSnapshot(
            _ snapshot: OpalFusion.Client.Session.Snapshot
        ) async {
            guard terminalOutcome == nil else {
                return
            }

            if snapshot.lastError == nil || snapshot.state.isConnected {
                preRoundTransportFailureRetryAttempt = 0
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
            guard snapshot.lastError == .transportUnavailable else {
                return false
            }

            let nextAttempt = preRoundTransportFailureRetryAttempt + 1
            guard reconnectPolicy.allowsRetry(forAttempt: nextAttempt) else {
                return false
            }

            preRoundTransportFailureRetryAttempt = nextAttempt
            return true
        }

        private func finalize(with outcome: TerminalOutcome) async {
            await OpalDiagnostics.withTraceID(traceID) {
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
                    OpalDiagnostics.record(
                        OpalDiagnostics.Event.cashFusionSessionFinalized,
                        category: OpalDiagnostics.Category.cashFusion,
                        level: outcome.diagnosticsLevel,
                        fields: [
                            OpalDiagnostics.Field.operation("cash_fusion_session_finalize"),
                            OpalDiagnostics.Field.module(),
                            OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.outcome, outcome.diagnosticsName)
                        ]
                    )
                } catch {
                    OpalDiagnostics.record(
                        OpalDiagnostics.Event.cashFusionSessionFinalized,
                        category: OpalDiagnostics.Category.cashFusion,
                        level: .error,
                        fields: [
                            OpalDiagnostics.Field.operation("cash_fusion_session_finalize"),
                            OpalDiagnostics.Field.module(),
                            OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.outcome, outcome.diagnosticsName)
                        ] + OpalDiagnostics.Field.errorFields(
                            for: error,
                            fallback: OpalDiagnostics.ErrorCode.cashFusionSessionFailed
                        )
                    )
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

private extension OpalFusion.Client.ReconnectPolicy {
    func allowsRetry(forAttempt attempt: Int) -> Bool {
        guard maximumAttempts != 0, attempt > 0 else {
            return false
        }

        guard maximumAttempts != nil || initialDelay > .zero else {
            return false
        }

        if let maximumAttempts, attempt > maximumAttempts {
            return false
        }

        return true
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

    var diagnosticsLevel: OpalDiagnostics.Level? {
        self == .failed ? .error : nil
    }
}
#endif
