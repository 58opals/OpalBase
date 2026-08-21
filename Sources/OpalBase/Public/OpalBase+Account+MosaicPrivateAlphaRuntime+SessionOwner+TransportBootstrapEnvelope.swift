// OpalBase+Account+MosaicPrivateAlphaRuntime+SessionOwner+TransportBootstrapEnvelope.swift

#if os(macOS)
import Foundation
import OpalCrypto
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime.SessionOwner {
    @_spi(MosaicPrivateAlpha)
    public func makeTransportBootstrapInbox(
        recipientEventIdentity: Data,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapRelayCapabilities,
        replayEntries: [OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapReplayEntry] = []
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapInbox {
        try await performTransportBootstrapDocumentOperation { proof in
            return try .init(
                FusionRuntime.TransportBootstrapInbox(
                    proof: proof,
                    binding: try binding.fusionBinding,
                    recipientEventIdentity: recipientEventIdentity,
                    capabilities: capabilities.fusionCapabilities(),
                    replayEntries: replayEntries.map(\.fusionEntry)
                )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func restoreTransportBootstrapPublication(
        canonicalEventBytes: Data,
        canonicalDocument: Data,
        senderEventIdentity: Data,
        recipientEventIdentity: Data,
        expectedOperationIdentifier: Data,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapPublication {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime.restoreTransportBootstrapPublication(
                    canonicalEventBytes: canonicalEventBytes,
                    canonicalDocument: canonicalDocument,
                    senderEventIdentity: senderEventIdentity,
                    recipientEventIdentity: recipientEventIdentity,
                    proof: proof,
                    binding: try binding.fusionBinding,
                    expectedOperationIdentifier:
                        expectedOperationIdentifier,
                    currentUnixSeconds: currentUnixSeconds
                )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func sealTransportBootstrapAuthorizationKeyDocument(
        _ document: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        recipientControlIdentity: Data,
        wrapperSigningKey: OpalCrypto.Secp256k1.SigningKey,
        reservedEventIdentities: Set<Data>,
        timestamps: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapLayerTimestamps
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapPublication {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .sealTransportBootstrapAuthorizationKeyDocument(
                        document.storage.value,
                        proof: proof,
                        binding: try binding.fusionBinding,
                        conductorControlSigningKey:
                            conductorControlSigningKey,
                        recipientControlIdentity: recipientControlIdentity,
                        wrapperSigningKey: wrapperSigningKey,
                        reservedEventIdentities: reservedEventIdentities,
                        timestamps: timestamps.fusionTimestamps
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func openTransportBootstrapAuthorizationKeyDocument(
        from canonicalEventBytes: Data,
        recipientControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapOpenedDocument<OpalBase.Account
            .MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument> {
        try await performTransportBootstrapDocumentOperation { proof in
            let opened = try FusionRuntime
                .openTransportBootstrapAuthorizationKeyDocument(
                    from: canonicalEventBytes,
                    proof: proof,
                    recipientControlSigningKey:
                        recipientControlSigningKey,
                    currentUnixSeconds: currentUnixSeconds
                )
            return .init(opened, projectDocument: { .init($0) })
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func sealTransportBootstrapControlMailboxClaim(
        _ claim: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaim,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        senderControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        recipientControlIdentity: Data,
        wrapperSigningKey: OpalCrypto.Secp256k1.SigningKey,
        reservedEventIdentities: Set<Data>,
        timestamps: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapLayerTimestamps
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapPublication {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime.sealTransportBootstrapControlMailboxClaim(
                    claim.storage.value,
                    proof: proof,
                    authorizationKey: authorizationKey.storage.value,
                    binding: try binding.fusionBinding,
                    senderControlSigningKey: senderControlSigningKey,
                    recipientControlIdentity: recipientControlIdentity,
                    wrapperSigningKey: wrapperSigningKey,
                    reservedEventIdentities: reservedEventIdentities,
                    timestamps: timestamps.fusionTimestamps
                )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func openTransportBootstrapControlMailboxClaim(
        from canonicalEventBytes: Data,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        recipientControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapOpenedDocument<OpalBase.Account
            .MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaim> {
        try await performTransportBootstrapDocumentOperation { proof in
            let opened = try FusionRuntime
                .openTransportBootstrapControlMailboxClaim(
                    from: canonicalEventBytes,
                    proof: proof,
                    authorizationKey: authorizationKey.storage.value,
                    recipientControlSigningKey:
                        recipientControlSigningKey,
                    currentUnixSeconds: currentUnixSeconds
                )
            return .init(opened, projectDocument: { .init($0) })
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func sealTransportBootstrapBlindResponseSet(
        _ responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        recipientContributorControlIdentity: Data,
        wrapperSigningKey: OpalCrypto.Secp256k1.SigningKey,
        reservedEventIdentities: Set<Data>,
        timestamps: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapLayerTimestamps
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapPublication {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime.sealTransportBootstrapBlindResponseSet(
                    responseSet.storage.value,
                    proof: proof,
                    authorizationKey: authorizationKey.storage.value,
                    claimSet: claimSet.storage.value,
                    binding: try binding.fusionBinding,
                    conductorControlSigningKey:
                        conductorControlSigningKey,
                    recipientContributorControlIdentity:
                        recipientContributorControlIdentity,
                    wrapperSigningKey: wrapperSigningKey,
                    reservedEventIdentities: reservedEventIdentities,
                    timestamps: timestamps.fusionTimestamps
                )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func openTransportBootstrapBlindResponseSet(
        from canonicalEventBytes: Data,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        recipientContributorControlSigningKey:
            OpalCrypto.Secp256k1.SigningKey,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapOpenedDocument<OpalBase.Account
            .MosaicPrivateAlphaRuntime.TransportBootstrapBlindResponseSet> {
        try await performTransportBootstrapDocumentOperation { proof in
            let opened = try FusionRuntime
                .openTransportBootstrapBlindResponseSet(
                    from: canonicalEventBytes,
                    proof: proof,
                    authorizationKey: authorizationKey.storage.value,
                    claimSet: claimSet.storage.value,
                    recipientContributorControlSigningKey:
                        recipientContributorControlSigningKey,
                    currentUnixSeconds: currentUnixSeconds
                )
            return .init(opened, projectDocument: { .init($0) })
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func sealTransportBootstrapAnonymousMailboxRegistration(
        _ registration: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistration,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        anonymousSenderSigningKey: OpalCrypto.Secp256k1.SigningKey,
        conductorControlIdentity: Data,
        wrapperSigningKey: OpalCrypto.Secp256k1.SigningKey,
        reservedEventIdentities: Set<Data>,
        timestamps: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapLayerTimestamps
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapPublication {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .sealTransportBootstrapAnonymousMailboxRegistration(
                        registration.storage.value,
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        claimSet: claimSet.storage.value,
                        responseSet: responseSet.storage.value,
                        binding: try binding.fusionBinding,
                        anonymousSenderSigningKey:
                            anonymousSenderSigningKey,
                        conductorControlIdentity: conductorControlIdentity,
                        wrapperSigningKey: wrapperSigningKey,
                        reservedEventIdentities: reservedEventIdentities,
                        timestamps: timestamps.fusionTimestamps
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func openTransportBootstrapAnonymousMailboxRegistration(
        from canonicalEventBytes: Data,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapOpenedDocument<OpalBase.Account
            .MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistration> {
        try await performTransportBootstrapDocumentOperation { proof in
            let opened = try FusionRuntime
                .openTransportBootstrapAnonymousMailboxRegistration(
                    from: canonicalEventBytes,
                    proof: proof,
                    authorizationKey: authorizationKey.storage.value,
                    claimSet: claimSet.storage.value,
                    responseSet: responseSet.storage.value,
                    conductorControlSigningKey:
                        conductorControlSigningKey,
                    currentUnixSeconds: currentUnixSeconds
                )
            return .init(opened, projectDocument: { .init($0) })
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func sealTransportBootstrapAnonymousMailboxAssignment(
        _ assignment: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxAssignment,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        registration: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistration,
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        wrapperSigningKey: OpalCrypto.Secp256k1.SigningKey,
        reservedEventIdentities: Set<Data>,
        timestamps: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapLayerTimestamps
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapPublication {
        try await performTransportBootstrapDocumentOperation { proof in
            return .init(
                try FusionRuntime
                    .sealTransportBootstrapAnonymousMailboxAssignment(
                        assignment.storage.value,
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        claimSet: claimSet.storage.value,
                        responseSet: responseSet.storage.value,
                        registration: registration.storage.value,
                        binding: try binding.fusionBinding,
                        conductorControlSigningKey:
                            conductorControlSigningKey,
                        wrapperSigningKey: wrapperSigningKey,
                        reservedEventIdentities: reservedEventIdentities,
                        timestamps: timestamps.fusionTimestamps
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func openTransportBootstrapAnonymousMailboxAssignment(
        from canonicalEventBytes: Data,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        registration: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistration,
        anonymousRecipientSigningKey: OpalCrypto.Secp256k1.SigningKey,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapOpenedDocument<OpalBase.Account
            .MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxAssignment> {
        try await performTransportBootstrapDocumentOperation { proof in
            let opened = try FusionRuntime
                .openTransportBootstrapAnonymousMailboxAssignment(
                    from: canonicalEventBytes,
                    proof: proof,
                    authorizationKey: authorizationKey.storage.value,
                    claimSet: claimSet.storage.value,
                    responseSet: responseSet.storage.value,
                    registration: registration.storage.value,
                    anonymousRecipientSigningKey:
                        anonymousRecipientSigningKey,
                    currentUnixSeconds: currentUnixSeconds
                )
            return .init(opened, projectDocument: { .init($0) })
        }
    }
}
#endif
