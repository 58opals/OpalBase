// OpalBase+Account+MosaicPrivateAlphaRuntime+PostManifestMailboxes.swift

#if os(macOS)
import Foundation
import OpalCrypto
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Canonical authenticated documents shared by both bootstrap roles.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestMailboxDocuments: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let authorizationKey: Data
        @_spi(MosaicPrivateAlpha) public let controlClaimSet: Data
        @_spi(MosaicPrivateAlpha) public let blindResponseSet: Data
        @_spi(MosaicPrivateAlpha) public let registrationSet: Data
        @_spi(MosaicPrivateAlpha) public let acknowledgementSet: Data

        @_spi(MosaicPrivateAlpha)
        public init(
            authorizationKey: Data,
            controlClaimSet: Data,
            blindResponseSet: Data,
            registrationSet: Data,
            acknowledgementSet: Data
        ) {
            self.authorizationKey = authorizationKey
            self.controlClaimSet = controlClaimSet
            self.blindResponseSet = blindResponseSet
            self.registrationSet = registrationSet
            self.acknowledgementSet = acknowledgementSet
        }
    }

    /// Persisted contributor bootstrap material needed to reconstruct live mailbox capabilities.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestContributorMailboxArchive: Sendable {
        @_spi(MosaicPrivateAlpha) public let documents:
            PostManifestMailboxDocuments
        @_spi(MosaicPrivateAlpha) public let registration: Data
        @_spi(MosaicPrivateAlpha) public let assignment: Data
        @_spi(MosaicPrivateAlpha) public let contributorControlIdentity: Data
        @_spi(MosaicPrivateAlpha) public let localControlRecipientSigningKey:
            OpalCrypto.Secp256k1.SigningKey

        @_spi(MosaicPrivateAlpha)
        public init(
            documents: PostManifestMailboxDocuments,
            registration: Data,
            assignment: Data,
            contributorControlIdentity: Data,
            localControlRecipientSigningKey:
                OpalCrypto.Secp256k1.SigningKey
        ) {
            self.documents = documents
            self.registration = registration
            self.assignment = assignment
            self.contributorControlIdentity = contributorControlIdentity
            self.localControlRecipientSigningKey =
                localControlRecipientSigningKey
        }
    }

    @_spi(MosaicPrivateAlpha)
    public struct PostManifestConductorMailboxAssignment: Sendable {
        @_spi(MosaicPrivateAlpha) public let registration: Data
        @_spi(MosaicPrivateAlpha) public let assignment: Data
        @_spi(MosaicPrivateAlpha) public let recipientPrivateKeys:
            [OpalCrypto.Secp256k1.PrivateKey]

        @_spi(MosaicPrivateAlpha)
        public init(
            registration: Data,
            assignment: Data,
            recipientPrivateKeys: [OpalCrypto.Secp256k1.PrivateKey]
        ) {
            self.registration = registration
            self.assignment = assignment
            self.recipientPrivateKeys = recipientPrivateKeys
        }
    }

    /// Persisted conductor bootstrap material needed to restore every anonymous recipient key.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestConductorMailboxArchive: Sendable {
        @_spi(MosaicPrivateAlpha) public let documents:
            PostManifestMailboxDocuments
        @_spi(MosaicPrivateAlpha) public let assignments:
            [PostManifestConductorMailboxAssignment]
        @_spi(MosaicPrivateAlpha) public let localControlRecipientSigningKey:
            OpalCrypto.Secp256k1.SigningKey

        @_spi(MosaicPrivateAlpha)
        public init(
            documents: PostManifestMailboxDocuments,
            assignments: [PostManifestConductorMailboxAssignment],
            localControlRecipientSigningKey:
                OpalCrypto.Secp256k1.SigningKey
        ) {
            self.documents = documents
            self.assignments = assignments
            self.localControlRecipientSigningKey =
                localControlRecipientSigningKey
        }
    }

    /// Package-validated live mailbox projection reconstructed from authenticated app state.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestMailboxDistribution: Sendable {
        @_spi(MosaicPrivateAlpha) public let binding: Binding
        @_spi(MosaicPrivateAlpha) public let localControlIdentity: Data
        @_spi(MosaicPrivateAlpha) public let isConductor: Bool
        @_spi(MosaicPrivateAlpha) public let controlClaimSetDigest: Data
        @_spi(MosaicPrivateAlpha) public let registrationSetDigest: Data
        @_spi(MosaicPrivateAlpha) public let acknowledgementSetDigest: Data
        @_spi(MosaicPrivateAlpha) public let authenticatedDocuments: [Data]

        let fusionDistribution: OpalFusion.MosaicPrivateAlphaRuntime
            .TransportBootstrapMailboxDistribution

        init(
            binding: Binding,
            localControlIdentity: Data,
            isConductor: Bool,
            distribution: OpalFusion.MosaicPrivateAlphaRuntime
                .TransportBootstrapMailboxDistribution
        ) {
            self.binding = binding
            self.localControlIdentity = localControlIdentity
            self.isConductor = isConductor
            controlClaimSetDigest = distribution.controlClaimSetDigest
            registrationSetDigest = distribution.registrationSetDigest
            acknowledgementSetDigest = distribution.acknowledgementSetDigest
            authenticatedDocuments = distribution.authenticatedDocuments
            fusionDistribution = distribution
        }
    }
}
#endif
