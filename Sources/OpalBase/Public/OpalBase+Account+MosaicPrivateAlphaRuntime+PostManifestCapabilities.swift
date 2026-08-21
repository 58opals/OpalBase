// OpalBase+Account+MosaicPrivateAlphaRuntime+PostManifestCapabilities.swift

#if os(macOS)
import Foundation
import OpalCrypto
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public enum PostManifestJournal: Sendable, Equatable {
        case admission
        case publication
        case terminal
    }

    /// Synchronous atomic storage for Fusion's three canonical companion journals.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestJournalPersistence: Sendable {
        let load: @Sendable (PostManifestJournal, Binding) throws -> Data?
        let compareAndSwap: @Sendable (
            PostManifestJournal,
            Binding,
            Data?,
            Data
        ) throws -> Data

        @_spi(MosaicPrivateAlpha)
        public init(
            load: @escaping @Sendable (
                PostManifestJournal,
                Binding
            ) throws -> Data?,
            compareAndSwap: @escaping @Sendable (
                PostManifestJournal,
                Binding,
                Data?,
                Data
            ) throws -> Data
        ) {
            self.load = load
            self.compareAndSwap = compareAndSwap
        }
    }

    @_spi(MosaicPrivateAlpha)
    public enum PostManifestRoutePurpose: Sendable, Equatable {
        case inboundControl
        case inboundAnonymous
        case outboundControl
        case outboundAnonymousComponents
        case outboundAnonymousBCHSignatures

        init(
            _ purpose: OpalFusion.MosaicPrivateAlphaRuntime
                .PostManifestRoutePurpose
        ) {
            switch purpose {
            case .inboundControl: self = .inboundControl
            case .inboundAnonymous: self = .inboundAnonymous
            case .outboundControl: self = .outboundControl
            case .outboundAnonymousComponents:
                self = .outboundAnonymousComponents
            case .outboundAnonymousBCHSignatures:
                self = .outboundAnonymousBCHSignatures
            }
        }
    }

    /// Package-derived request for isolated routes to one exact recipient.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestRouteRequest: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let binding: Binding
        @_spi(MosaicPrivateAlpha) public let purpose:
            PostManifestRoutePurpose
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let relayEndpointIdentifiers: [String]

        init(
            _ request: OpalFusion.MosaicPrivateAlphaRuntime
                .PostManifestRouteRequest
        ) {
            binding = .init(request.binding)
            purpose = .init(request.purpose)
            recipientEventIdentity = request.recipientEventIdentity
            relayEndpointIdentifiers = request.relayEndpointIdentifiers
        }
    }

    /// App-provisioned routes for one package-derived recipient request.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestProvisionedRouteGroup: Sendable {
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let routes:
            [PostManifestProvisionedRoute]

        @_spi(MosaicPrivateAlpha)
        public init(
            recipientEventIdentity: Data,
            routes: [PostManifestProvisionedRoute]
        ) {
            self.recipientEventIdentity = recipientEventIdentity
            self.routes = routes
        }

        var fusionGroup: OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestProvisionedRouteGroup {
            .init(
                recipientEventIdentity: recipientEventIdentity,
                routes: routes.map { $0.fusionRoute() }
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public enum PostManifestPublicationKind: Sendable, Equatable {
        case playerCommit
        case anonymousComponents
        case preSignAcknowledgement
        case localBCHSignatures
        case conductorAggregate

        init(
            _ kind: OpalFusion.MosaicPrivateAlphaRuntime
                .PostManifestPublicationKind
        ) {
            switch kind {
            case .playerCommit: self = .playerCommit
            case .anonymousComponents: self = .anonymousComponents
            case .preSignAcknowledgement:
                self = .preSignAcknowledgement
            case .localBCHSignatures: self = .localBCHSignatures
            case .conductorAggregate: self = .conductorAggregate
            }
        }
    }

    @_spi(MosaicPrivateAlpha)
    public struct PostManifestAnonymousPublicationRequest:
        Sendable,
        Equatable {
        @_spi(MosaicPrivateAlpha) public let kind:
            PostManifestPublicationKind
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentity: Data

        init(
            _ request: OpalFusion.MosaicPrivateAlphaRuntime
                .PostManifestAnonymousPublicationRequest
        ) {
            kind = .init(request.kind)
            recipientEventIdentity = request.recipientEventIdentity
        }
    }

    /// App-owned Tor route and bounded-buffer policy for post-manifest work.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestRelayCapabilities: Sendable {
        let provisionRoutes: @Sendable ([PostManifestRouteRequest]) async throws
            -> [PostManifestProvisionedRouteGroup]
        let makeSubscriptionIdentifier: @Sendable (
            PostManifestRouteRequest,
            String
        ) throws -> String
        let awaitAnonymousPublicationPermit: @Sendable (
            PostManifestAnonymousPublicationRequest
        ) async throws -> Void
        let maximumSubscriptionIdentifierByteCount: Int
        let maximumPendingEventCount: Int
        let maximumPendingRelayOutputCount: Int

        @_spi(MosaicPrivateAlpha)
        public init(
            provisionRoutes: @escaping @Sendable (
                [PostManifestRouteRequest]
            ) async throws -> [PostManifestProvisionedRouteGroup],
            makeSubscriptionIdentifier: @escaping @Sendable (
                PostManifestRouteRequest,
                String
            ) throws -> String,
            awaitAnonymousPublicationPermit: @escaping @Sendable (
                PostManifestAnonymousPublicationRequest
            ) async throws -> Void = { _ in },
            maximumSubscriptionIdentifierByteCount: Int,
            maximumPendingEventCount: Int = 256,
            maximumPendingRelayOutputCount: Int = 64
        ) {
            self.provisionRoutes = provisionRoutes
            self.makeSubscriptionIdentifier = makeSubscriptionIdentifier
            self.awaitAnonymousPublicationPermit =
                awaitAnonymousPublicationPermit
            self.maximumSubscriptionIdentifierByteCount =
                maximumSubscriptionIdentifierByteCount
            self.maximumPendingEventCount = maximumPendingEventCount
            self.maximumPendingRelayOutputCount =
                maximumPendingRelayOutputCount
        }

        func fusionCapabilities() -> OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestRelayCapabilities {
            let provisionRoutes = provisionRoutes
            let makeSubscriptionIdentifier = makeSubscriptionIdentifier
            let awaitPermit = awaitAnonymousPublicationPermit
            return .init(
                provisionRoutes: { requests in
                    try await provisionRoutes(
                        requests.map(PostManifestRouteRequest.init)
                    ).map(\.fusionGroup)
                },
                makeSubscriptionIdentifier: { request, endpoint in
                    try makeSubscriptionIdentifier(
                        .init(request),
                        endpoint
                    )
                },
                awaitAnonymousPublicationPermit: { request in
                    try await awaitPermit(.init(request))
                },
                maximumSubscriptionIdentifierByteCount:
                    maximumSubscriptionIdentifierByteCount,
                maximumPendingEventCount: maximumPendingEventCount,
                maximumPendingRelayOutputCount:
                    maximumPendingRelayOutputCount
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public enum PostManifestPhase: Sendable, Equatable {
        case discovery
        case candidateSetAgreement
        case admission
        case controlRosterAgreement
        case roleElection
        case nonceAllocation
        case manifestAgreement
        case walletReservation
        case groupedCommitment
        case anonymousComponentSubmission
        case transcriptAgreement
        case bchSigning

        init(_ phase: OpalFusion.MosaicPrivateAlphaRuntime.Phase) {
            switch phase {
            case .discovery: self = .discovery
            case .candidateSetAgreement: self = .candidateSetAgreement
            case .admission: self = .admission
            case .controlRosterAgreement: self = .controlRosterAgreement
            case .roleElection: self = .roleElection
            case .nonceAllocation: self = .nonceAllocation
            case .manifestAgreement: self = .manifestAgreement
            case .walletReservation: self = .walletReservation
            case .groupedCommitment: self = .groupedCommitment
            case .anonymousComponentSubmission:
                self = .anonymousComponentSubmission
            case .transcriptAgreement: self = .transcriptAgreement
            case .bchSigning: self = .bchSigning
            }
        }
    }

    @_spi(MosaicPrivateAlpha)
    public struct PostManifestTimestampRequest: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentity: Data?
        @_spi(MosaicPrivateAlpha) public let phase: PostManifestPhase
        @_spi(MosaicPrivateAlpha) public let sequence: UInt64
        @_spi(MosaicPrivateAlpha) public let expiryUnixSeconds: UInt64

        init(
            _ request: OpalFusion.MosaicPrivateAlphaRuntime
                .PostManifestTimestampRequest
        ) {
            recipientEventIdentity = request.recipientEventIdentity
            phase = .init(request.phase)
            sequence = request.sequence
            expiryUnixSeconds = request.expiryUnixSeconds
        }
    }

    @_spi(MosaicPrivateAlpha)
    public struct PostManifestLayerTimestamps: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let phaseStartUnixSeconds: UInt64
        @_spi(MosaicPrivateAlpha) public let currentUnixSeconds: UInt64
        @_spi(MosaicPrivateAlpha) public let sealCreatedAt: UInt64
        @_spi(MosaicPrivateAlpha) public let giftWrapCreatedAt: UInt64

        @_spi(MosaicPrivateAlpha)
        public init(
            phaseStartUnixSeconds: UInt64,
            currentUnixSeconds: UInt64,
            sealCreatedAt: UInt64,
            giftWrapCreatedAt: UInt64
        ) {
            self.phaseStartUnixSeconds = phaseStartUnixSeconds
            self.currentUnixSeconds = currentUnixSeconds
            self.sealCreatedAt = sealCreatedAt
            self.giftWrapCreatedAt = giftWrapCreatedAt
        }

        var fusionTimestamps: OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestLayerTimestamps {
            .init(
                phaseStartUnixSeconds: phaseStartUnixSeconds,
                currentUnixSeconds: currentUnixSeconds,
                sealCreatedAt: sealCreatedAt,
                giftWrapCreatedAt: giftWrapCreatedAt
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public struct PostManifestTimingCapabilities: Sendable {
        let currentUnixSeconds: @Sendable () -> UInt64
        let makeLayerTimestamps: @Sendable (
            PostManifestTimestampRequest
        ) throws -> PostManifestLayerTimestamps

        @_spi(MosaicPrivateAlpha)
        public init(
            currentUnixSeconds: @escaping @Sendable () -> UInt64,
            makeLayerTimestamps: @escaping @Sendable (
                PostManifestTimestampRequest
            ) throws -> PostManifestLayerTimestamps
        ) {
            self.currentUnixSeconds = currentUnixSeconds
            self.makeLayerTimestamps = makeLayerTimestamps
        }

        func fusionCapabilities() -> OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestTimingCapabilities {
            let currentUnixSeconds = currentUnixSeconds
            let makeLayerTimestamps = makeLayerTimestamps
            return .init(
                currentUnixSeconds: currentUnixSeconds,
                makeLayerTimestamps: {
                    try makeLayerTimestamps(.init($0)).fusionTimestamps
                }
            )
        }
    }

    /// Complete app-owned effect boundary for one post-manifest execution.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestRuntimeCapabilities: Sendable {
        let relays: PostManifestRelayCapabilities
        let timing: PostManifestTimingCapabilities
        let journals: PostManifestJournalPersistence
        let maximumPendingInputCount: Int

        @_spi(MosaicPrivateAlpha)
        public init(
            relays: PostManifestRelayCapabilities,
            timing: PostManifestTimingCapabilities,
            journals: PostManifestJournalPersistence,
            maximumPendingInputCount: Int = 256
        ) {
            self.relays = relays
            self.timing = timing
            self.journals = journals
            self.maximumPendingInputCount = maximumPendingInputCount
        }

        func fusionCapabilities(
            mailboxes: OpalFusion.MosaicPrivateAlphaRuntime
                .PostManifestMailboxCapabilities
        ) -> OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestRuntimeCapabilities {
            let journals = journals
            return .init(
                mailboxes: mailboxes,
                relays: relays.fusionCapabilities(),
                timing: timing.fusionCapabilities(),
                admissionPersistence: .init(
                    load: {
                        try journals.load(.admission, .init($0))
                    },
                    compareAndSwap: {
                        try journals.compareAndSwap(
                            .admission,
                            .init($0),
                            $1,
                            $2
                        )
                    }
                ),
                publicationPersistence: .init(
                    load: {
                        try journals.load(.publication, .init($0))
                    },
                    compareAndSwap: {
                        try journals.compareAndSwap(
                            .publication,
                            .init($0),
                            $1,
                            $2
                        )
                    }
                ),
                terminalPersistence: .init(
                    load: {
                        try journals.load(.terminal, .init($0))
                    },
                    compareAndSwap: {
                        try journals.compareAndSwap(
                            .terminal,
                            .init($0),
                            $1,
                            $2
                        )
                    }
                ),
                maximumPendingInputCount: maximumPendingInputCount
            )
        }
    }
}
#endif
