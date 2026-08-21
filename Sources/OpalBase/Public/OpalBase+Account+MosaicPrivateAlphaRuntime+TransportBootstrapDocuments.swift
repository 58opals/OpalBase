// OpalBase+Account+MosaicPrivateAlphaRuntime+TransportBootstrapDocuments.swift

#if os(macOS)
import Foundation
import OpalCrypto
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    typealias FusionRuntime = OpalFusion.MosaicPrivateAlphaRuntime

    /// Authenticated roster and deadline projection for application-owned bootstrap orchestration.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapRoster: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let roundIdentifier: Data
        @_spi(MosaicPrivateAlpha) public let relaySetDigest: Data
        @_spi(MosaicPrivateAlpha) public let relayEndpointIdentifiers: [String]
        @_spi(MosaicPrivateAlpha) public let controlIdentities: [Data]
        @_spi(MosaicPrivateAlpha) public let contributorControlIdentities:
            [Data]
        @_spi(MosaicPrivateAlpha) public let conductorControlIdentity: Data
        @_spi(MosaicPrivateAlpha) public let preManifestEventIdentities: [Data]
        @_spi(MosaicPrivateAlpha) public let phaseStartUnixSeconds: UInt64
        @_spi(MosaicPrivateAlpha) public let walletReservationDeadlineUnixSeconds:
            UInt64

        init(_ proof: FusionRuntime.PrivateDeploymentProof) {
            roundIdentifier = proof.roundIdentifier
            relaySetDigest = proof.relaySetDigest
            relayEndpointIdentifiers = proof.relayEndpointIdentifiers
            controlIdentities = proof.controlIdentities
            contributorControlIdentities = proof.contributorControlIdentities
            conductorControlIdentity = proof.conductorControlIdentity
            preManifestEventIdentities = proof.preManifestEventIdentities
            phaseStartUnixSeconds = proof.phaseStartUnixSeconds
            walletReservationDeadlineUnixSeconds =
                proof.walletReservationDeadlineUnixSeconds
        }
    }

    /// Conductor-authenticated attempt-exclusive RFC 9474 verification-key document.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapAuthorizationKeyDocument:
        Sendable,
        Equatable
    {
        @_spi(MosaicPrivateAlpha) public let verificationKeySubjectPublicKeyInfo:
            Data
        @_spi(MosaicPrivateAlpha) public let digest: Data
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data

        let storage: MosaicPrivateAlphaTransportBootstrapStorage<
            FusionRuntime.TransportBootstrapAuthorizationKeyDocument
        >

        init(
            _ document: FusionRuntime.TransportBootstrapAuthorizationKeyDocument
        ) {
            verificationKeySubjectPublicKeyInfo = document.verificationKey
                .subjectPublicKeyInfo
            digest = document.digest
            canonicalDocument = document.canonicalDocument
            storage = .init(document)
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.verificationKeySubjectPublicKeyInfo
                == rhs.verificationKeySubjectPublicKeyInfo
                && lhs.digest == rhs.digest
                && lhs.canonicalDocument == rhs.canonicalDocument
        }
    }

    /// Contributor-local recoverable RFC 9474 request; its recovery bytes remain secret.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapAnonymousMailboxRequest: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let anonymousSenderEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let blindedMessage: Data
        @_spi(MosaicPrivateAlpha) public let recoveryState: Data

        let storage: MosaicPrivateAlphaTransportBootstrapStorage<
            FusionRuntime.TransportBootstrapAnonymousMailboxRequest
        >

        init(
            _ request: FusionRuntime.TransportBootstrapAnonymousMailboxRequest
        ) {
            anonymousSenderEventIdentity = request.anonymousSenderEventIdentity
            blindedMessage = request.blindedMessage
            recoveryState = request.recoveryState.rawRepresentation
            storage = .init(request)
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.anonymousSenderEventIdentity
                == rhs.anonymousSenderEventIdentity
                && lhs.blindedMessage == rhs.blindedMessage
                && lhs.recoveryState == rhs.recoveryState
        }
    }

    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapControlMailboxClaim: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let controlIdentity: Data
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let blindedMessage: Data?
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data

        let storage: MosaicPrivateAlphaTransportBootstrapStorage<
            FusionRuntime.TransportBootstrapControlMailboxClaim
        >

        init(_ claim: FusionRuntime.TransportBootstrapControlMailboxClaim) {
            controlIdentity = claim.controlIdentity
            recipientEventIdentity = claim.recipientEventIdentity
            blindedMessage = claim.blindedMessage
            canonicalDocument = claim.canonicalDocument
            storage = .init(claim)
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.controlIdentity == rhs.controlIdentity
                && lhs.recipientEventIdentity == rhs.recipientEventIdentity
                && lhs.blindedMessage == rhs.blindedMessage
                && lhs.canonicalDocument == rhs.canonicalDocument
        }
    }

    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapControlMailboxClaimSet:
        Sendable,
        Equatable
    {
        @_spi(MosaicPrivateAlpha) public let claims:
            [TransportBootstrapControlMailboxClaim]
        @_spi(MosaicPrivateAlpha) public let digest: Data
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data

        let storage: MosaicPrivateAlphaTransportBootstrapStorage<
            FusionRuntime.TransportBootstrapControlMailboxClaimSet
        >

        init(_ set: FusionRuntime.TransportBootstrapControlMailboxClaimSet) {
            claims = set.claims.map(TransportBootstrapControlMailboxClaim.init)
            digest = set.digest
            canonicalDocument = set.canonicalDocument
            storage = .init(set)
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.claims == rhs.claims
                && lhs.digest == rhs.digest
                && lhs.canonicalDocument == rhs.canonicalDocument
        }
    }

    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapBlindResponseSet: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let claimSetDigest: Data
        @_spi(MosaicPrivateAlpha) public let digest: Data
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data

        let storage: MosaicPrivateAlphaTransportBootstrapStorage<
            FusionRuntime.TransportBootstrapBlindResponseSet
        >

        init(_ set: FusionRuntime.TransportBootstrapBlindResponseSet) {
            claimSetDigest = set.claimSetDigest
            digest = set.digest
            canonicalDocument = set.canonicalDocument
            storage = .init(set)
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.claimSetDigest == rhs.claimSetDigest
                && lhs.digest == rhs.digest
                && lhs.canonicalDocument == rhs.canonicalDocument
        }
    }

    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapAnonymousMailboxRegistration:
        Sendable,
        Equatable
    {
        @_spi(MosaicPrivateAlpha) public let anonymousSenderEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let authorizationSpentIdentifier: Data
        @_spi(MosaicPrivateAlpha) public let digest: Data
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data

        let storage: MosaicPrivateAlphaTransportBootstrapStorage<
            FusionRuntime.TransportBootstrapAnonymousMailboxRegistration
        >

        init(
            _ registration:
                FusionRuntime.TransportBootstrapAnonymousMailboxRegistration
        ) {
            anonymousSenderEventIdentity =
                registration.anonymousSenderEventIdentity
            authorizationSpentIdentifier =
                registration.authorizationSpentIdentifier
            digest = registration.digest
            canonicalDocument = registration.canonicalDocument
            storage = .init(registration)
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.anonymousSenderEventIdentity
                == rhs.anonymousSenderEventIdentity
                && lhs.authorizationSpentIdentifier
                    == rhs.authorizationSpentIdentifier
                && lhs.digest == rhs.digest
                && lhs.canonicalDocument == rhs.canonicalDocument
        }
    }

    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapAnonymousMailboxAssignment:
        Sendable,
        Equatable
    {
        @_spi(MosaicPrivateAlpha) public let registrationDigest: Data
        @_spi(MosaicPrivateAlpha) public let anonymousRecipientEventIdentity:
            Data
        @_spi(MosaicPrivateAlpha) public let mailboxBundleCommitment: Data
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentities: [Data]
        @_spi(MosaicPrivateAlpha) public let digest: Data
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data

        let storage: MosaicPrivateAlphaTransportBootstrapStorage<
            FusionRuntime.TransportBootstrapAnonymousMailboxAssignment
        >

        init(
            _ assignment:
                FusionRuntime.TransportBootstrapAnonymousMailboxAssignment
        ) {
            registrationDigest = assignment.registrationDigest
            anonymousRecipientEventIdentity =
                assignment.anonymousRecipientEventIdentity
            mailboxBundleCommitment = assignment.mailboxBundleCommitment
            recipientEventIdentities = assignment.recipientEventIdentities
            digest = assignment.digest
            canonicalDocument = assignment.canonicalDocument
            storage = .init(assignment)
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.registrationDigest == rhs.registrationDigest
                && lhs.anonymousRecipientEventIdentity
                    == rhs.anonymousRecipientEventIdentity
                && lhs.mailboxBundleCommitment == rhs.mailboxBundleCommitment
                && lhs.recipientEventIdentities == rhs.recipientEventIdentities
                && lhs.digest == rhs.digest
                && lhs.canonicalDocument == rhs.canonicalDocument
        }
    }

    /// Conductor-local assignment plus the exact private capabilities that back it.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapConductorMailboxAssignment: Sendable {
        @_spi(MosaicPrivateAlpha) public let assignment:
            TransportBootstrapAnonymousMailboxAssignment
        @_spi(MosaicPrivateAlpha) public let recipientPrivateKeys:
            [OpalCrypto.Secp256k1.PrivateKey]

        let storage: MosaicPrivateAlphaTransportBootstrapStorage<
            FusionRuntime.TransportBootstrapConductorMailboxAssignment
        >

        init(
            _ assignment:
                FusionRuntime.TransportBootstrapConductorMailboxAssignment,
            recipientPrivateKeys: [OpalCrypto.Secp256k1.PrivateKey]
        ) {
            self.assignment = .init(assignment.assignment)
            self.recipientPrivateKeys = recipientPrivateKeys
            storage = .init(assignment)
        }
    }

    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapAnonymousMailboxRegistrationSet:
        Sendable,
        Equatable
    {
        @_spi(MosaicPrivateAlpha) public let mailboxBundleCommitments: [Data]
        @_spi(MosaicPrivateAlpha) public let digest: Data
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data

        let storage: MosaicPrivateAlphaTransportBootstrapStorage<
            FusionRuntime.TransportBootstrapAnonymousMailboxRegistrationSet
        >

        init(
            _ set:
                FusionRuntime.TransportBootstrapAnonymousMailboxRegistrationSet
        ) {
            mailboxBundleCommitments = set.mailboxBundleCommitments
            digest = set.digest
            canonicalDocument = set.canonicalDocument
            storage = .init(set)
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.mailboxBundleCommitments == rhs.mailboxBundleCommitments
                && lhs.digest == rhs.digest
                && lhs.canonicalDocument == rhs.canonicalDocument
        }
    }

    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapRegistrationSetAcknowledgement:
        Sendable,
        Equatable
    {
        @_spi(MosaicPrivateAlpha) public let controlIdentity: Data
        @_spi(MosaicPrivateAlpha) public let registrationSetDigest: Data
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data

        let storage: MosaicPrivateAlphaTransportBootstrapStorage<
            FusionRuntime.TransportBootstrapRegistrationSetAcknowledgement
        >

        init(
            _ acknowledgement:
                FusionRuntime.TransportBootstrapRegistrationSetAcknowledgement
        ) {
            controlIdentity = acknowledgement.controlIdentity
            registrationSetDigest = acknowledgement.registrationSetDigest
            canonicalDocument = acknowledgement.canonicalDocument
            storage = .init(acknowledgement)
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.controlIdentity == rhs.controlIdentity
                && lhs.registrationSetDigest == rhs.registrationSetDigest
                && lhs.canonicalDocument == rhs.canonicalDocument
        }
    }

    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapRegistrationSetAcknowledgementSet:
        Sendable,
        Equatable
    {
        @_spi(MosaicPrivateAlpha) public let registrationSetDigest: Data
        @_spi(MosaicPrivateAlpha) public let digest: Data
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data

        let storage: MosaicPrivateAlphaTransportBootstrapStorage<
            FusionRuntime
                .TransportBootstrapRegistrationSetAcknowledgementSet
        >

        init(
            _ set: FusionRuntime
                .TransportBootstrapRegistrationSetAcknowledgementSet
        ) {
            registrationSetDigest = set.registrationSetDigest
            digest = set.digest
            canonicalDocument = set.canonicalDocument
            storage = .init(set)
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.registrationSetDigest == rhs.registrationSetDigest
                && lhs.digest == rhs.digest
                && lhs.canonicalDocument == rhs.canonicalDocument
        }
    }

    /// Caller-owned NIP-59 cover timestamps for one bootstrap publication.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapLayerTimestamps: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let currentUnixSeconds: UInt64
        @_spi(MosaicPrivateAlpha) public let rumorCreatedAt: UInt64
        @_spi(MosaicPrivateAlpha) public let sealCreatedAt: UInt64
        @_spi(MosaicPrivateAlpha) public let giftWrapCreatedAt: UInt64

        @_spi(MosaicPrivateAlpha)
        public init(
            currentUnixSeconds: UInt64,
            rumorCreatedAt: UInt64,
            sealCreatedAt: UInt64,
            giftWrapCreatedAt: UInt64
        ) {
            self.currentUnixSeconds = currentUnixSeconds
            self.rumorCreatedAt = rumorCreatedAt
            self.sealCreatedAt = sealCreatedAt
            self.giftWrapCreatedAt = giftWrapCreatedAt
        }

        var fusionTimestamps: FusionRuntime.TransportBootstrapLayerTimestamps {
            .init(
                currentUnixSeconds: currentUnixSeconds,
                rumorCreatedAt: rumorCreatedAt,
                sealCreatedAt: sealCreatedAt,
                giftWrapCreatedAt: giftWrapCreatedAt
            )
        }
    }
}

final class MosaicPrivateAlphaTransportBootstrapStorage<Value: Sendable>:
    Sendable
{
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
#endif
