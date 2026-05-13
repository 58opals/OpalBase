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

        var hasStarted = false
        var hasStoppedWrappedSession = false
        var terminalOutcome: TerminalOutcome?

        init(
            reservation: CashFusionReservation,
            wrappedSession: any CashFusionWrappedSession,
            observerSink: CashFusionObserverSink
        ) {
            self.reservation = reservation
            self.wrappedSession = wrappedSession
            self.observerSink = observerSink
        }

        public func start() async {
            guard terminalOutcome == nil, hasStarted == false else {
                return
            }

            hasStarted = true
            await wrappedSession.start()
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
            } catch {
                assertionFailure("CashFusion reservation cleanup failed: \(error)")
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
#endif
