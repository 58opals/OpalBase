// OpalBase+Account+MosaicPrivateAlphaRuntime+SessionOwner+TransportBootstrapDocuments.swift

#if os(macOS)
import Foundation
import OpalCrypto
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime.SessionOwner {
    /// Projects the package-authenticated roster without exposing the Fusion proof.
    @_spi(MosaicPrivateAlpha)
    public func transportBootstrapRoster() async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapRoster {
        try await performTransportBootstrapDocumentOperation { proof in
            .init(proof)
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func makeTransportBootstrapAuthorizationKeyDocument(
        authorizationSigningKey: OpalCrypto.RSABSSA.SigningKey,
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        auxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapAuthorizationKeyDocument {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .makeTransportBootstrapAuthorizationKeyDocument(
                        proof: proof,
                        authorizationSigningKey: authorizationSigningKey,
                        conductorControlSigningKey:
                            conductorControlSigningKey,
                        auxiliaryRandomness: auxiliaryRandomness
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func loadTransportBootstrapAuthorizationKeyDocument(
        from canonicalDocument: Data,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapAuthorizationKeyDocument {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .loadTransportBootstrapAuthorizationKeyDocument(
                        from: canonicalDocument,
                        proof: proof,
                        currentUnixSeconds: currentUnixSeconds
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func makeTransportBootstrapAnonymousMailboxRequest(
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        authorizationNonce: Data,
        anonymousSenderPrivateKey: OpalCrypto.Secp256k1.PrivateKey
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapAnonymousMailboxRequest {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .makeTransportBootstrapAnonymousMailboxRequest(
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        authorizationNonce: authorizationNonce,
                        anonymousSenderPrivateKey: anonymousSenderPrivateKey
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func restoreTransportBootstrapAnonymousMailboxRequest(
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        authorizationNonce: Data,
        anonymousSenderPrivateKey: OpalCrypto.Secp256k1.PrivateKey,
        recoveryState: Data,
        expectedBlindedMessage: Data
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapAnonymousMailboxRequest {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .restoreTransportBootstrapAnonymousMailboxRequest(
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        authorizationNonce: authorizationNonce,
                        anonymousSenderPrivateKey: anonymousSenderPrivateKey,
                        recoveryState: try .init(
                            rawRepresentation: recoveryState
                        ),
                        expectedBlindedMessage: expectedBlindedMessage
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func makeTransportBootstrapControlMailboxClaim(
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        controlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        recipientEventVerificationKey:
            OpalCrypto.Signature.BIP340.VerificationKey,
        anonymousMailboxRequest: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRequest?,
        auxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapControlMailboxClaim {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime.makeTransportBootstrapControlMailboxClaim(
                    proof: proof,
                    authorizationKey: authorizationKey.storage.value,
                    controlSigningKey: controlSigningKey,
                    recipientEventVerificationKey:
                        recipientEventVerificationKey,
                    anonymousMailboxRequest:
                        anonymousMailboxRequest?.storage.value,
                    auxiliaryRandomness: auxiliaryRandomness
                )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func loadTransportBootstrapControlMailboxClaim(
        from canonicalDocument: Data,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapControlMailboxClaim {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime.loadTransportBootstrapControlMailboxClaim(
                    from: canonicalDocument,
                    proof: proof,
                    authorizationKey: authorizationKey.storage.value,
                    currentUnixSeconds: currentUnixSeconds
                )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func makeTransportBootstrapControlMailboxClaimSet(
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claims: [OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaim]
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapControlMailboxClaimSet {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .makeTransportBootstrapControlMailboxClaimSet(
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        claims: claims.map { $0.storage.value }
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func loadTransportBootstrapControlMailboxClaimSet(
        from canonicalDocument: Data,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapControlMailboxClaimSet {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .loadTransportBootstrapControlMailboxClaimSet(
                        from: canonicalDocument,
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        currentUnixSeconds: currentUnixSeconds
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func makeTransportBootstrapBlindResponseSet(
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        authorizationSigningKey: OpalCrypto.RSABSSA.SigningKey,
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        auxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapBlindResponseSet {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime.makeTransportBootstrapBlindResponseSet(
                    proof: proof,
                    authorizationKey: authorizationKey.storage.value,
                    claimSet: claimSet.storage.value,
                    authorizationSigningKey: authorizationSigningKey,
                    conductorControlSigningKey: conductorControlSigningKey,
                    auxiliaryRandomness: auxiliaryRandomness
                )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func loadTransportBootstrapBlindResponseSet(
        from canonicalDocument: Data,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapBlindResponseSet {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime.loadTransportBootstrapBlindResponseSet(
                    from: canonicalDocument,
                    proof: proof,
                    authorizationKey: authorizationKey.storage.value,
                    claimSet: claimSet.storage.value,
                    currentUnixSeconds: currentUnixSeconds
                )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func makeTransportBootstrapAnonymousMailboxRegistration(
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        contributorControlIdentity: Data,
        request: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRequest,
        anonymousSenderSigningKey: OpalCrypto.Secp256k1.SigningKey,
        auxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapAnonymousMailboxRegistration {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .makeTransportBootstrapAnonymousMailboxRegistration(
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        claimSet: claimSet.storage.value,
                        responseSet: responseSet.storage.value,
                        contributorControlIdentity:
                            contributorControlIdentity,
                        request: request.storage.value,
                        anonymousSenderSigningKey:
                            anonymousSenderSigningKey,
                        auxiliaryRandomness: auxiliaryRandomness
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func loadTransportBootstrapAnonymousMailboxRegistration(
        from canonicalDocument: Data,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapAnonymousMailboxRegistration {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .loadTransportBootstrapAnonymousMailboxRegistration(
                        from: canonicalDocument,
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        claimSet: claimSet.storage.value,
                        responseSet: responseSet.storage.value,
                        currentUnixSeconds: currentUnixSeconds
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func makeTransportBootstrapAnonymousMailboxAssignment(
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        registration: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistration,
        recipientPrivateKeys: [OpalCrypto.Secp256k1.PrivateKey],
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        auxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapConductorMailboxAssignment {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .makeTransportBootstrapAnonymousMailboxAssignment(
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        claimSet: claimSet.storage.value,
                        responseSet: responseSet.storage.value,
                        registration: registration.storage.value,
                        recipientPrivateKeys: recipientPrivateKeys,
                        conductorControlSigningKey:
                            conductorControlSigningKey,
                        auxiliaryRandomness: auxiliaryRandomness,
                        currentUnixSeconds: currentUnixSeconds
                    ),
                recipientPrivateKeys: recipientPrivateKeys
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func loadTransportBootstrapAnonymousMailboxAssignment(
        from canonicalDocument: Data,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        registration: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistration,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapAnonymousMailboxAssignment {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .loadTransportBootstrapAnonymousMailboxAssignment(
                        from: canonicalDocument,
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        claimSet: claimSet.storage.value,
                        responseSet: responseSet.storage.value,
                        registration: registration.storage.value,
                        currentUnixSeconds: currentUnixSeconds
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func restoreTransportBootstrapConductorMailboxAssignment(
        from canonicalDocument: Data,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        registration: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistration,
        recipientPrivateKeys: [OpalCrypto.Secp256k1.PrivateKey],
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapConductorMailboxAssignment {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .restoreTransportBootstrapConductorMailboxAssignment(
                        from: canonicalDocument,
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        claimSet: claimSet.storage.value,
                        responseSet: responseSet.storage.value,
                        registration: registration.storage.value,
                        recipientPrivateKeys: recipientPrivateKeys,
                        currentUnixSeconds: currentUnixSeconds
                    ),
                recipientPrivateKeys: recipientPrivateKeys
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func makeTransportBootstrapAnonymousMailboxRegistrationSet(
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        registrations: [OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistration],
        conductorAssignments: [OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapConductorMailboxAssignment],
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        auxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapAnonymousMailboxRegistrationSet {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .makeTransportBootstrapAnonymousMailboxRegistrationSet(
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        claimSet: claimSet.storage.value,
                        responseSet: responseSet.storage.value,
                        registrations: registrations.map {
                            $0.storage.value
                        },
                        conductorAssignments: conductorAssignments.map {
                            $0.storage.value
                        },
                        conductorControlSigningKey:
                            conductorControlSigningKey,
                        auxiliaryRandomness: auxiliaryRandomness,
                        currentUnixSeconds: currentUnixSeconds
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func loadTransportBootstrapAnonymousMailboxRegistrationSet(
        from canonicalDocument: Data,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapAnonymousMailboxRegistrationSet {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .loadTransportBootstrapAnonymousMailboxRegistrationSet(
                        from: canonicalDocument,
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        claimSet: claimSet.storage.value,
                        responseSet: responseSet.storage.value,
                        currentUnixSeconds: currentUnixSeconds
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func makeTransportBootstrapRegistrationSetAcknowledgement(
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        registrationSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistrationSet,
        controlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        localAnonymousMailboxAssignment: OpalBase.Account
            .MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxAssignment?,
        auxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapRegistrationSetAcknowledgement {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .makeTransportBootstrapRegistrationSetAcknowledgement(
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        claimSet: claimSet.storage.value,
                        responseSet: responseSet.storage.value,
                        registrationSet: registrationSet.storage.value,
                        controlSigningKey: controlSigningKey,
                        localAnonymousMailboxAssignment:
                            localAnonymousMailboxAssignment?.storage.value,
                        auxiliaryRandomness: auxiliaryRandomness,
                        currentUnixSeconds: currentUnixSeconds
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func loadTransportBootstrapRegistrationSetAcknowledgement(
        from canonicalDocument: Data,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        registrationSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistrationSet,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapRegistrationSetAcknowledgement {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .loadTransportBootstrapRegistrationSetAcknowledgement(
                        from: canonicalDocument,
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        claimSet: claimSet.storage.value,
                        responseSet: responseSet.storage.value,
                        registrationSet: registrationSet.storage.value,
                        currentUnixSeconds: currentUnixSeconds
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func makeTransportBootstrapRegistrationSetAcknowledgementSet(
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        registrationSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistrationSet,
        acknowledgements: [OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapRegistrationSetAcknowledgement],
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapRegistrationSetAcknowledgementSet {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .makeTransportBootstrapRegistrationSetAcknowledgementSet(
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        claimSet: claimSet.storage.value,
                        responseSet: responseSet.storage.value,
                        registrationSet: registrationSet.storage.value,
                        acknowledgements: acknowledgements.map {
                            $0.storage.value
                        },
                        currentUnixSeconds: currentUnixSeconds
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func loadTransportBootstrapRegistrationSetAcknowledgementSet(
        from canonicalDocument: Data,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        registrationSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistrationSet,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapRegistrationSetAcknowledgementSet {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .loadTransportBootstrapRegistrationSetAcknowledgementSet(
                        from: canonicalDocument,
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        claimSet: claimSet.storage.value,
                        responseSet: responseSet.storage.value,
                        registrationSet: registrationSet.storage.value,
                        currentUnixSeconds: currentUnixSeconds
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func makePostManifestMailboxDocuments(
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        registrationSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistrationSet,
        acknowledgementSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapRegistrationSetAcknowledgementSet,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .PostManifestMailboxDocuments {
        try await performTransportBootstrapDocumentOperation { proof in
            _ = try Self.loadCommonMailboxDocuments(
                .init(
                    authorizationKey: authorizationKey.canonicalDocument,
                    controlClaimSet: claimSet.canonicalDocument,
                    blindResponseSet: responseSet.canonicalDocument,
                    registrationSet: registrationSet.canonicalDocument,
                    acknowledgementSet: acknowledgementSet.canonicalDocument
                ),
                proof: proof,
                currentUnixSeconds: currentUnixSeconds
            )
            return .init(
                authorizationKey: authorizationKey.canonicalDocument,
                controlClaimSet: claimSet.canonicalDocument,
                blindResponseSet: responseSet.canonicalDocument,
                registrationSet: registrationSet.canonicalDocument,
                acknowledgementSet: acknowledgementSet.canonicalDocument
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func makePostManifestContributorMailboxArchive(
        documents: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PostManifestMailboxDocuments,
        registration: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistration,
        assignment: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxAssignment,
        contributorControlIdentity: Data,
        localControlRecipientSigningKey:
            OpalCrypto.Secp256k1.SigningKey
    ) -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .PostManifestContributorMailboxArchive {
        .init(
            documents: documents,
            registration: registration.canonicalDocument,
            assignment: assignment.canonicalDocument,
            contributorControlIdentity: contributorControlIdentity,
            localControlRecipientSigningKey:
                localControlRecipientSigningKey
        )
    }

    @_spi(MosaicPrivateAlpha)
    public func makePostManifestConductorMailboxArchive(
        documents: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PostManifestMailboxDocuments,
        registrations: [OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistration],
        assignments: [OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapConductorMailboxAssignment],
        localControlRecipientSigningKey:
            OpalCrypto.Secp256k1.SigningKey
    ) throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .PostManifestConductorMailboxArchive {
        var registrationByDigest: [Data: OpalBase.Account
            .MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistration] = [:]
        for registration in registrations {
            guard registrationByDigest.updateValue(
                registration,
                forKey: registration.digest
            ) == nil else {
                throw OpalBase.Account.MosaicPrivateAlphaRuntime.Failure
                    .invalidRecoveryState
            }
        }
        guard assignments.count == registrations.count else {
            throw OpalBase.Account.MosaicPrivateAlphaRuntime.Failure
                .invalidRecoveryState
        }
        var assignedRegistrationDigests: Set<Data> = []
        let archiveAssignments = try assignments.map { assignment in
            let registrationDigest = assignment.assignment.registrationDigest
            guard assignedRegistrationDigests.insert(
                registrationDigest
            ).inserted,
                let registration = registrationByDigest[
                    registrationDigest
                ] else {
                throw OpalBase.Account.MosaicPrivateAlphaRuntime.Failure
                    .invalidRecoveryState
            }
            return OpalBase.Account.MosaicPrivateAlphaRuntime
                .PostManifestConductorMailboxAssignment(
                    registration: registration.canonicalDocument,
                    assignment: assignment.assignment.canonicalDocument,
                    recipientPrivateKeys: assignment.recipientPrivateKeys
                )
        }
        return .init(
            documents: documents,
            assignments: archiveAssignments,
            localControlRecipientSigningKey:
                localControlRecipientSigningKey
        )
    }

    func performTransportBootstrapDocumentOperation<Result>(
        _ operation: (FusionRuntime.PrivateDeploymentProof)
            async throws -> Result
    ) async throws -> Result {
        guard execution == nil else {
            throw OpalBase.Account.MosaicPrivateAlphaRuntime.Failure
                .invalidRecoveryState
        }
        guard !sessionOperationIsInProgress,
              !constructionIsInProgress else {
            throw OpalBase.Account.MosaicPrivateAlphaRuntime.Failure
                .operationInProgress
        }
        sessionOperationIsInProgress = true
        defer { sessionOperationIsInProgress = false }
        do {
            let proof = try await owner
                .makeTransportBootstrapPrivateDeploymentProof()
            return try await operation(proof)
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch let failure
            as OpalBase.Account.MosaicPrivateAlphaRuntime.Failure {
            throw failure
        } catch {
            throw OpalBase.Account.MosaicPrivateAlphaRuntime.Failure(error)
        }
    }
}
#endif
