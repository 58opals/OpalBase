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

        public init(
            isConnected: Bool,
            round: Round?,
            lastError: LastError?
        ) {
            self.isConnected = isConnected
            self.round = round
            self.lastError = lastError
        }
    }
}

extension _OpalBase.Account.CashFusionSessionStatus {
    init(snapshot: OpalFusion.Client.Session.Snapshot) {
        self.init(
            isConnected: snapshot.state.isConnected,
            round: snapshot.state.round.map(Self.makeRound(_:)),
            lastError: snapshot.lastError.map(Self.makeLastError(_:))
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
}

extension _OpalBase.Account.CashFusionSession {
    public func makePublicStatus() async -> OpalBase.Account.CashFusionSessionStatus {
        let sessionSnapshot = await snapshot()
        return .init(snapshot: sessionSnapshot)
    }
}
