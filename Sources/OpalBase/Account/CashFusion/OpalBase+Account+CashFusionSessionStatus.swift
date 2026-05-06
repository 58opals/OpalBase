#if os(macOS)
// OpalBase+Account+CashFusionSessionStatus.swift

import Foundation
import OpalFusion

extension _OpalBase.Account {
    public struct CashFusionSessionStatus: Sendable, Equatable {
        public enum Phase: String, Sendable, Equatable {
            case idle
            case connecting
            case registeringInputs
            case awaitingCommitments
            case awaitingBlindSignatures
            case assemblingTransaction
            case blame
            case completed
        }

        public enum CompletionStatus: String, Sendable, Equatable {
            case success
            case coordinatorRejected
            case hostRejected
            case protocolIncompatible
            case transportFailed
            case blameRequired
        }

        public enum Activity: String, Sendable, Equatable {
            case idle
            case connecting
            case running
            case retrying
            case failed
            case stopped
        }

        public enum LastError: String, Sendable, Equatable {
            case invalidConfiguration
            case transportUnavailable
            case coordinatorRejected
            case hostRejected
            case protocolIncompatible
            case blameRequired
            case notImplemented
        }

        public struct Round: Sendable, Equatable {
            public let identifier: String
            public let phase: Phase
            public let participantCount: Int?
            public let completionStatus: CompletionStatus?
            public let isTerminal: Bool

            public init(
                identifier: String,
                phase: Phase,
                participantCount: Int? = nil,
                completionStatus: CompletionStatus? = nil,
                isTerminal: Bool = false
            ) {
                self.identifier = identifier
                self.phase = phase
                self.participantCount = participantCount
                self.completionStatus = completionStatus
                self.isTerminal = isTerminal
            }
        }

        public let isConnected: Bool
        public let round: Round?
        public let lastError: LastError?
        public let lastErrorSummary: String?
        public let activity: Activity
        public let retryAttempt: Int?
        public let nextRetryDelayMilliseconds: Int?

        public init(
            isConnected: Bool,
            round: Round?,
            lastError: LastError?,
            lastErrorSummary: String? = nil,
            activity: Activity = .idle,
            retryAttempt: Int? = nil,
            nextRetryDelayMilliseconds: Int? = nil
        ) {
            self.isConnected = isConnected
            self.round = round
            self.lastError = lastError
            self.lastErrorSummary = lastErrorSummary
            self.activity = activity
            self.retryAttempt = retryAttempt
            self.nextRetryDelayMilliseconds = nextRetryDelayMilliseconds
        }
    }
}

extension _OpalBase.Account.CashFusionSessionStatus {
    init(snapshot: OpalFusion.Client.Session.Snapshot) {
        self.init(
            isConnected: snapshot.state.isConnected,
            round: snapshot.state.round.map(Self.makeRound(_:)),
            lastError: snapshot.lastError.map(Self.makeLastError(_:)),
            lastErrorSummary: snapshot.lastErrorSummary,
            activity: Self.makeActivity(snapshot.diagnostics.activity),
            retryAttempt: snapshot.diagnostics.retryAttempt,
            nextRetryDelayMilliseconds: snapshot.diagnostics.nextRetryDelayMilliseconds
        )
    }

    private static func makeRound(_ round: OpalFusion.Round.State) -> Round {
        .init(
            identifier: round.identifier.rawValue,
            phase: makePhase(round.phase),
            participantCount: round.participantCount,
            completionStatus: round.completionStatus.map(Self.makeCompletionStatus(_:)),
            isTerminal: round.isTerminal
        )
    }

    private static func makePhase(
        _ phase: OpalFusion.Round.Phase
    ) -> OpalBase.Account.CashFusionSessionStatus.Phase {
        switch phase {
        case .idle:
            return .idle
        case .connecting:
            return .connecting
        case .registeringInputs:
            return .registeringInputs
        case .awaitingCommitments:
            return .awaitingCommitments
        case .awaitingBlindSignatures:
            return .awaitingBlindSignatures
        case .assemblingTransaction:
            return .assemblingTransaction
        case .blame:
            return .blame
        case .completed:
            return .completed
        }
    }

    private static func makeCompletionStatus(
        _ completionStatus: OpalFusion.Round.CompletionStatus
    ) -> OpalBase.Account.CashFusionSessionStatus.CompletionStatus {
        switch completionStatus {
        case .success:
            return .success
        case .coordinatorRejected:
            return .coordinatorRejected
        case .hostRejected:
            return .hostRejected
        case .protocolIncompatible:
            return .protocolIncompatible
        case .transportFailed:
            return .transportFailed
        case .blameRequired:
            return .blameRequired
        }
    }

    private static func makeLastError(
        _ error: OpalFusion.Client.Error
    ) -> OpalBase.Account.CashFusionSessionStatus.LastError {
        switch error {
        case .invalidConfiguration:
            return .invalidConfiguration
        case .transportUnavailable:
            return .transportUnavailable
        case .coordinatorRejected:
            return .coordinatorRejected
        case .hostRejected:
            return .hostRejected
        case .protocolIncompatible:
            return .protocolIncompatible
        case .blameRequired:
            return .blameRequired
        case .notImplemented:
            return .notImplemented
        }
    }

    private static func makeActivity(
        _ activity: OpalFusion.Client.Diagnostics.Activity
    ) -> OpalBase.Account.CashFusionSessionStatus.Activity {
        switch activity {
        case .idle:
            return .idle
        case .connecting:
            return .connecting
        case .running:
            return .running
        case .retrying:
            return .retrying
        case .failed:
            return .failed
        case .stopped:
            return .stopped
        }
    }
}

extension _OpalBase.Account.CashFusionSession {
    public func makePublicStatus() async -> OpalBase.Account.CashFusionSessionStatus {
        let sessionSnapshot = await snapshot()
        return .init(snapshot: sessionSnapshot)
    }
}
#endif
