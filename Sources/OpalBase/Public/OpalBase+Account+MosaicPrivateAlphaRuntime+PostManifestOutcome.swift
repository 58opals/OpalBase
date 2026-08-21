// OpalBase+Account+MosaicPrivateAlphaRuntime+PostManifestOutcome.swift

#if os(macOS)
import Foundation
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public struct FusionRecoveryTransition: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let binding: Binding
        @_spi(MosaicPrivateAlpha) public let expectedSnapshot: Data?
        @_spi(MosaicPrivateAlpha) public let replacementSnapshot: Data
        @_spi(MosaicPrivateAlpha) public let replacementDigest: Data
        @_spi(MosaicPrivateAlpha) public let replacementRevision: UInt64
        @_spi(MosaicPrivateAlpha) public let transitionIdentifier: Data

        let fusionTransition: OpalFusion.MosaicPrivateAlphaRuntime
            .RecoveryTransition

        init(
            _ transition: OpalFusion.MosaicPrivateAlphaRuntime
                .RecoveryTransition
        ) {
            binding = .init(transition.binding)
            expectedSnapshot = transition.expectedSnapshot
            replacementSnapshot = transition.replacementSnapshot
            replacementDigest = transition.replacementDigest
            replacementRevision = transition.replacementRevision
            transitionIdentifier = transition.transitionIdentifier
            fusionTransition = transition
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.binding == rhs.binding
                && lhs.expectedSnapshot == rhs.expectedSnapshot
                && lhs.replacementSnapshot == rhs.replacementSnapshot
                && lhs.replacementDigest == rhs.replacementDigest
                && lhs.replacementRevision == rhs.replacementRevision
                && lhs.transitionIdentifier == rhs.transitionIdentifier
        }
    }

    /// App-owned atomic outer-record replacement for Fusion recovery bytes.
    @_spi(MosaicPrivateAlpha)
    public struct FusionRecoveryPersistence: Sendable {
        let persist: @Sendable (FusionRecoveryTransition) async throws -> Data

        @_spi(MosaicPrivateAlpha)
        public init(
            persist: @escaping @Sendable (
                FusionRecoveryTransition
            ) async throws -> Data
        ) {
            self.persist = persist
        }
    }

    @_spi(MosaicPrivateAlpha)
    public enum PostManifestRecoveryCause: Sendable, Equatable {
        case walletState
        case runtimeFailure
        case transportUnavailable
    }

    @_spi(MosaicPrivateAlpha)
    public enum PostManifestTerminalReason: Sendable, Equatable {
        case completed
        case aborted

        init(_ reason: OpalFusion.MosaicPrivateAlphaRuntime.TerminalReason) {
            switch reason {
            case .completed: self = .completed
            case .aborted: self = .aborted
            }
        }
    }

    /// Exact protocol cleanup evidence. Wallet disposition remains a separate authority.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestTerminalEvidence: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let binding: Binding
        @_spi(MosaicPrivateAlpha) public let reason:
            PostManifestTerminalReason
        @_spi(MosaicPrivateAlpha) public let evidenceIdentifier: Data
        @_spi(MosaicPrivateAlpha) public let recoveryRevision: UInt64
        @_spi(MosaicPrivateAlpha) public let recoverySnapshotDigest: Data
    }

    /// Application disposition after the sole runtime termination has been claimed.
    @_spi(MosaicPrivateAlpha)
    public enum PostManifestDisposition: Sendable, Equatable {
        case terminal(PostManifestTerminalEvidence)
        case recoveryRequired(
            PostManifestRecoveryCause,
            reservationReference: PostManifestReservationReference?
        )
        case alreadyClaimed
    }

    /// Exact public-event relay capability used for formation or terminal publication.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentRouteRequest: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let binding: Binding
        @_spi(MosaicPrivateAlpha) public let relayEndpointIdentifiers: [String]

        init(
            _ request: OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentRouteRequest
        ) {
            binding = .init(request.binding)
            relayEndpointIdentifiers = request.relayEndpointIdentifiers
        }
    }

    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentRelayCapabilities: Sendable {
        let provisionRoutes: @Sendable (PrivateDeploymentRouteRequest)
            async throws -> [PostManifestProvisionedRoute]
        let maximumPendingRelayOutputCount: Int

        @_spi(MosaicPrivateAlpha)
        public init(
            provisionRoutes: @escaping @Sendable (
                PrivateDeploymentRouteRequest
            ) async throws -> [PostManifestProvisionedRoute],
            maximumPendingRelayOutputCount: Int = 64
        ) {
            self.provisionRoutes = provisionRoutes
            self.maximumPendingRelayOutputCount =
                maximumPendingRelayOutputCount
        }

        func fusionCapabilities() -> OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentRelayCapabilities {
            let provisionRoutes = provisionRoutes
            return .init(
                provisionRoutes: { request in
                    try await provisionRoutes(.init(request)).map {
                        $0.fusionRoute()
                    }
                },
                maximumPendingRelayOutputCount:
                    maximumPendingRelayOutputCount
            )
        }
    }
}
#endif
