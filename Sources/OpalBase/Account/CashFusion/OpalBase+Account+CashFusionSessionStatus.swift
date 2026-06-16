// OpalBase+Account+CashFusionSessionStatus.swift

#if os(macOS)
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

        public enum Completion: String, Sendable, Equatable {
            case success
            case coordinatorRejected
            case hostRejected
            case protocolIncompatible
            case transportFailed
            case blameRequired
        }

        @available(*, deprecated, renamed: "Completion")
        public typealias CompletionStatus = Completion

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
            public let completionStatus: Completion?
            public let isTerminal: Bool

            public init(
                identifier: String,
                phase: Phase,
                participantCount: Int? = nil,
                completionStatus: Completion? = nil,
                isTerminal: Bool = false
            ) {
                self.identifier = identifier
                self.phase = phase
                self.participantCount = participantCount
                self.completionStatus = completionStatus
                self.isTerminal = isTerminal
            }
        }

        public struct Coordinator: Sendable, Equatable {
            public struct Queue: Sendable, Equatable {
                public let tierSatoshis: UInt64
                public let playerCount: UInt32?
                public let minimumPlayerCount: UInt32?
                public let maximumPlayerCount: UInt32?
                public let timeRemainingSeconds: UInt32?

                public init(
                    tierSatoshis: UInt64,
                    playerCount: UInt32? = nil,
                    minimumPlayerCount: UInt32? = nil,
                    maximumPlayerCount: UInt32? = nil,
                    timeRemainingSeconds: UInt32? = nil
                ) {
                    self.tierSatoshis = tierSatoshis
                    self.playerCount = playerCount
                    self.minimumPlayerCount = minimumPlayerCount
                    self.maximumPlayerCount = maximumPlayerCount
                    self.timeRemainingSeconds = timeRemainingSeconds
                }
            }

            @available(*, deprecated, renamed: "Queue")
            public typealias QueueStatus = Queue

            public let updateSequence: UInt64
            public let latestMessageKind: String?
            public let latestMessagePayloadByteCount: Int?
            public let queueStatus: Queue?

            public init(
                updateSequence: UInt64 = 0,
                latestMessageKind: String? = nil,
                latestMessagePayloadByteCount: Int? = nil,
                queueStatus: Queue? = nil
            ) {
                self.updateSequence = updateSequence
                self.latestMessageKind = latestMessageKind
                self.latestMessagePayloadByteCount = latestMessagePayloadByteCount
                self.queueStatus = queueStatus
            }
        }

        @available(*, deprecated, renamed: "Coordinator")
        public typealias CoordinatorStatus = Coordinator

        public let isConnected: Bool
        public let round: Round?
        public let lastError: LastError?
        public let lastErrorSummary: String?
        public let activity: Activity
        public let retryAttempt: Int?
        public let nextRetryDelayMilliseconds: Int?
        public let coordinatorStatus: Coordinator
        public let completedLocalOutputs: [OpalBase.Transaction.Output.Unspent]

        public init(
            isConnected: Bool,
            round: Round?,
            lastError: LastError?,
            lastErrorSummary: String? = nil,
            activity: Activity = .idle,
            retryAttempt: Int? = nil,
            nextRetryDelayMilliseconds: Int? = nil,
            coordinatorStatus: Coordinator = .init(),
            completedLocalOutputs: [OpalBase.Transaction.Output.Unspent] = []
        ) {
            self.isConnected = isConnected
            self.round = round
            self.lastError = lastError
            self.lastErrorSummary = lastErrorSummary
            self.activity = activity
            self.retryAttempt = retryAttempt
            self.nextRetryDelayMilliseconds = nextRetryDelayMilliseconds
            self.coordinatorStatus = coordinatorStatus
            self.completedLocalOutputs = completedLocalOutputs
        }
    }
}

extension _OpalBase.Account.CashFusionSessionStatus {
    init(
        snapshot: OpalFusion.Client.Session.Snapshot,
        completedLocalOutputs: [OpalBase.Transaction.Output.Unspent] = [],
        activityOverride: OpalBase.Account.CashFusionSessionStatus.Activity? = nil,
        retryAttempt: Int? = nil
    ) {
        self.init(
            isConnected: snapshot.state.isConnected,
            round: snapshot.state.round.map(Self.makeRound(_:)),
            lastError: snapshot.lastError.map(Self.makeLastError(_:)),
            lastErrorSummary: snapshot.lastErrorSummary,
            activity: activityOverride ?? Self.makeActivity(snapshot),
            retryAttempt: retryAttempt,
            nextRetryDelayMilliseconds: nil,
            coordinatorStatus: Self.makeCoordinator(snapshot.coordinatorStatus),
            completedLocalOutputs: completedLocalOutputs
        )
    }

    private static func makeRound(_ round: OpalFusion.Round.State) -> Round {
        .init(
            identifier: round.identifier.rawValue,
            phase: makePhase(round.phase),
            participantCount: round.participantCount,
            completionStatus: round.completionStatus.map(Self.makeCompletion(_:)),
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

    private static func makeCompletion(
        _ completionStatus: OpalFusion.Round.CompletionStatus
    ) -> OpalBase.Account.CashFusionSessionStatus.Completion {
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
        _ snapshot: OpalFusion.Client.Session.Snapshot
    ) -> OpalBase.Account.CashFusionSessionStatus.Activity {
        if snapshot.lastError != nil, snapshot.state.isConnected == false {
            return .failed
        }

        if snapshot.state.round != nil {
            return .running
        }

        if snapshot.state.isConnected {
            return .idle
        }

        return .idle
    }

    private static func makeCoordinator(
        _ coordinatorStatus: OpalFusion.Client.Session.Snapshot.CoordinatorStatus
    ) -> OpalBase.Account.CashFusionSessionStatus.Coordinator {
        .init(
            updateSequence: coordinatorStatus.updateSequence,
            latestMessageKind: coordinatorStatus.latestInboundMessageKind,
            latestMessagePayloadByteCount: coordinatorStatus.latestInboundPayloadByteCount,
            queueStatus: coordinatorStatus.queueStatus.map(Self.makeQueue(_:))
        )
    }

    private static func makeQueue(
        _ queueStatus: OpalFusion.Client.Session.Snapshot.CoordinatorStatus.TierQueue
    ) -> OpalBase.Account.CashFusionSessionStatus.Coordinator.Queue {
        .init(
            tierSatoshis: queueStatus.tierSatoshis,
            playerCount: queueStatus.players,
            minimumPlayerCount: queueStatus.minPlayers,
            maximumPlayerCount: queueStatus.maxPlayers,
            timeRemainingSeconds: queueStatus.timeRemaining
        )
    }
}

extension _OpalBase.Account.CashFusionSession {
    public func makePublicStatus() async -> OpalBase.Account.CashFusionSessionStatus {
        let sessionSnapshot = await publicStatusSnapshot()
        let completedLocalOutputs = await completedLocalOutputs(for: sessionSnapshot)
        return .init(
            snapshot: sessionSnapshot,
            completedLocalOutputs: completedLocalOutputs,
            activityOverride: publicStatusActivityOverride,
            retryAttempt: publicStatusRetryAttempt
        )
    }

    private var publicStatusActivityOverride: OpalBase.Account.CashFusionSessionStatus.Activity? {
        switch terminalOutcome {
        case .failed?:
            return .failed
        case .stopped?:
            return .stopped
        case .success?:
            return nil
        case .none:
            return publicStatusRetryAttempt == nil ? nil : .retrying
        }
    }

    private var publicStatusRetryAttempt: Int? {
        preRoundTransportFailureRetryAttempt > 0 ? preRoundTransportFailureRetryAttempt : nil
    }
    
    private func publicStatusSnapshot() async -> OpalFusion.Client.Session.Snapshot {
        if terminalOutcome == .success, let successfulTerminalSnapshot {
            return successfulTerminalSnapshot
        }
        
        return await currentSnapshot
    }

    private func completedLocalOutputs(
        for sessionSnapshot: OpalFusion.Client.Session.Snapshot
    ) async -> [OpalBase.Transaction.Output.Unspent] {
        guard let round = sessionSnapshot.state.round,
              round.phase == .completed,
              round.completionStatus == .success,
              round.isTerminal else {
            return []
        }

        return await reservation.completedLocalOutputs(for: round.identifier)
    }
}
#endif
