// OpalBase+Account+MosaicPrivateAlphaRuntime+PostManifestHost.swift

#if os(macOS)
import Foundation
import OpalCrypto
import Security
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Purpose-separated non-exportable conductor keys restored by the application.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestConductorAuthorizationKeys: @unchecked Sendable {
        let component: SecKey
        let bchSignature: SecKey

        @_spi(MosaicPrivateAlpha)
        public init(component: SecKey, bchSignature: SecKey) {
            self.component = component
            self.bchSignature = bchSignature
        }
    }

    @_spi(MosaicPrivateAlpha)
    public struct PostManifestReservationReference: Sendable, Hashable {
        @_spi(MosaicPrivateAlpha) public let identifier: UUID
        @_spi(MosaicPrivateAlpha) public let generation: UInt64

        init(_ reference: OpalFusion.Host.MosaicReservationReference) {
            identifier = reference.identifier
            generation = reference.generation
        }
    }

    /// Minimum app-visible lease identity needed to locate persisted contributor secrets.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestReservationLease: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let reference:
            PostManifestReservationReference
        @_spi(MosaicPrivateAlpha) public let expiresAt: Date

        init(_ lease: OpalFusion.Host.MosaicReservationLease) {
            reference = .init(lease.reference)
            expiresAt = lease.expiresAt
        }
    }

    /// App-restored, purpose-separated material for one package-selected contributor slot.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestComponentSlotSecrets: Sendable {
        @_spi(MosaicPrivateAlpha) public let salt: Data
        @_spi(MosaicPrivateAlpha) public let pedersenNonce:
            OpalCrypto.Pedersen.Nonce
        @_spi(MosaicPrivateAlpha) public let communicationPrivateKey:
            OpalCrypto.Secp256k1.PrivateKey
        @_spi(MosaicPrivateAlpha) public let componentEnvelopePrivateKey:
            OpalCrypto.Secp256k1.PrivateKey
        @_spi(MosaicPrivateAlpha) public let bchSignatureEnvelopePrivateKey:
            OpalCrypto.Secp256k1.PrivateKey
        @_spi(MosaicPrivateAlpha) public let componentAuthorizationNonce: Data
        @_spi(MosaicPrivateAlpha) public let bchSignatureAuthorizationNonce: Data
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentity: Data

        @_spi(MosaicPrivateAlpha)
        public init(
            salt: Data,
            pedersenNonce: OpalCrypto.Pedersen.Nonce,
            communicationPrivateKey: OpalCrypto.Secp256k1.PrivateKey,
            componentEnvelopePrivateKey: OpalCrypto.Secp256k1.PrivateKey,
            bchSignatureEnvelopePrivateKey:
                OpalCrypto.Secp256k1.PrivateKey,
            componentAuthorizationNonce: Data,
            bchSignatureAuthorizationNonce: Data,
            recipientEventIdentity: Data
        ) {
            self.salt = salt
            self.pedersenNonce = pedersenNonce
            self.communicationPrivateKey = communicationPrivateKey
            self.componentEnvelopePrivateKey = componentEnvelopePrivateKey
            self.bchSignatureEnvelopePrivateKey =
                bchSignatureEnvelopePrivateKey
            self.componentAuthorizationNonce = componentAuthorizationNonce
            self.bchSignatureAuthorizationNonce =
                bchSignatureAuthorizationNonce
            self.recipientEventIdentity = recipientEventIdentity
        }

        var fusionSecrets: OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestComponentSlotSecrets {
            .init(
                salt: salt,
                pedersenNonce: pedersenNonce,
                communicationPrivateKey: communicationPrivateKey,
                componentEnvelopePrivateKey:
                    componentEnvelopePrivateKey,
                bchSignatureEnvelopePrivateKey:
                    bchSignatureEnvelopePrivateKey,
                componentAuthorizationNonce:
                    componentAuthorizationNonce,
                bchSignatureAuthorizationNonce:
                    bchSignatureAuthorizationNonce,
                recipientEventIdentity: recipientEventIdentity
            )
        }
    }

    /// Opaque app-authenticated authorization recovery for one contributor slot.
    ///
    /// The application must retain these bytes only in its authenticated attempt record and
    /// erase them with the attempt's terminal secret material.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestComponentSlotAuthorizationRecoveryState:
        Sendable,
        Equatable
    {
        @_spi(MosaicPrivateAlpha) public let componentRequest: Data
        @_spi(MosaicPrivateAlpha) public let bchSignatureRequest: Data

        @_spi(MosaicPrivateAlpha)
        public init(
            componentRequest: Data,
            bchSignatureRequest: Data
        ) {
            self.componentRequest = Data(componentRequest)
            self.bchSignatureRequest = Data(bchSignatureRequest)
        }

        init(
            _ state: OpalFusion.MosaicPrivateAlphaRuntime
                .PostManifestComponentSlotAuthorizationRecoveryState
        ) {
            self.init(
                componentRequest: state.componentRequest,
                bchSignatureRequest: state.bchSignatureRequest
            )
        }

        var fusionRecoveryState: OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestComponentSlotAuthorizationRecoveryState {
            .init(
                componentRequest: componentRequest,
                bchSignatureRequest: bchSignatureRequest
            )
        }
    }

    /// Exact authenticated event bytes admitted by the package runtime.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentEvent: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let canonicalEventBytes: Data
        @_spi(MosaicPrivateAlpha) public let acceptedAtUnixSeconds: UInt64

        @_spi(MosaicPrivateAlpha)
        public init(
            canonicalEventBytes: Data,
            acceptedAtUnixSeconds: UInt64
        ) {
            self.canonicalEventBytes = canonicalEventBytes
            self.acceptedAtUnixSeconds = acceptedAtUnixSeconds
        }

        var fusionEvent: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent {
            get throws {
                try .init(
                    canonicalEventBytes: canonicalEventBytes,
                    acceptedAtUnixSeconds: acceptedAtUnixSeconds
                )
            }
        }
    }

    /// One-use signing inputs for one package-constructed private-deployment event.
    ///
    /// Copies share the same claim. A second use fails with
    /// ``Failure/oneTimeCapabilityAlreadyClaimed`` before another signature is made.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentSigningMaterial: Sendable {
        let signingKey: OpalCrypto.Secp256k1.SigningKey
        let documentAuxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness
        let eventAuxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness
        private let oneTimeClaim = MosaicPrivateAlphaOneTimeClaim()

        @_spi(MosaicPrivateAlpha)
        public init(
            signingKey: OpalCrypto.Secp256k1.SigningKey,
            documentAuxiliaryRandomness:
                OpalCrypto.Signature.BIP340.AuxiliaryRandomness,
            eventAuxiliaryRandomness:
                OpalCrypto.Signature.BIP340.AuxiliaryRandomness
        ) {
            self.signingKey = signingKey
            self.documentAuxiliaryRandomness =
                documentAuxiliaryRandomness
            self.eventAuxiliaryRandomness = eventAuxiliaryRandomness
        }

        func claimFusionCapability() async throws -> OpalFusion
            .MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningCapability {
            try await oneTimeClaim.claim()
            return .init(
                signingKey: signingKey,
                documentAuxiliaryRandomness:
                    documentAuxiliaryRandomness,
                eventAuxiliaryRandomness: eventAuxiliaryRandomness
            )
        }
    }
}
#endif
