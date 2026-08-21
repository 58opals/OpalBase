// OpalBase+Account+MosaicPrivateAlphaRuntime+SessionOwner+TransportBootstrapConsensusEnvelope.swift

#if os(macOS)
import Foundation
import OpalCrypto
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime.SessionOwner {
    @_spi(MosaicPrivateAlpha)
    public func sealTransportBootstrapAnonymousMailboxRegistrationSet(
        _ registrationSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistrationSet,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        conductorAssignments: [OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapConductorMailboxAssignment],
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
                    .sealTransportBootstrapAnonymousMailboxRegistrationSet(
                        registrationSet.storage.value,
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        claimSet: claimSet.storage.value,
                        responseSet: responseSet.storage.value,
                        conductorAssignments: conductorAssignments.map {
                            $0.storage.value
                        },
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
    public func openTransportBootstrapAnonymousMailboxRegistrationSet(
        from canonicalEventBytes: Data,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        localAnonymousMailboxAssignment: OpalBase.Account
            .MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxAssignment?,
        recipientControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapOpenedDocument<OpalBase.Account
            .MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistrationSet> {
        try await performTransportBootstrapDocumentOperation { proof in
            let opened = try FusionRuntime
                .openTransportBootstrapAnonymousMailboxRegistrationSet(
                    from: canonicalEventBytes,
                    proof: proof,
                    authorizationKey: authorizationKey.storage.value,
                    claimSet: claimSet.storage.value,
                    responseSet: responseSet.storage.value,
                    localAnonymousMailboxAssignment:
                        localAnonymousMailboxAssignment?.storage.value,
                    recipientControlSigningKey:
                        recipientControlSigningKey,
                    currentUnixSeconds: currentUnixSeconds
                )
            return .init(opened, projectDocument: { .init($0) })
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func sealTransportBootstrapRegistrationSetAcknowledgement(
        _ acknowledgement: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapRegistrationSetAcknowledgement,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        registrationSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistrationSet,
        localAnonymousMailboxAssignment: OpalBase.Account
            .MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxAssignment?,
        senderControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
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
                    .sealTransportBootstrapRegistrationSetAcknowledgement(
                        acknowledgement.storage.value,
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        claimSet: claimSet.storage.value,
                        responseSet: responseSet.storage.value,
                        registrationSet: registrationSet.storage.value,
                        localAnonymousMailboxAssignment:
                            localAnonymousMailboxAssignment?.storage.value,
                        binding: try binding.fusionBinding,
                        senderControlSigningKey: senderControlSigningKey,
                        conductorControlIdentity: conductorControlIdentity,
                        wrapperSigningKey: wrapperSigningKey,
                        reservedEventIdentities: reservedEventIdentities,
                        timestamps: timestamps.fusionTimestamps
                    )
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func openTransportBootstrapRegistrationSetAcknowledgement(
        from canonicalEventBytes: Data,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        registrationSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistrationSet,
        conductorAssignments: [OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapConductorMailboxAssignment],
        conductorControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapOpenedDocument<OpalBase.Account
            .MosaicPrivateAlphaRuntime
            .TransportBootstrapRegistrationSetAcknowledgement> {
        try await performTransportBootstrapDocumentOperation { proof in
            let opened = try FusionRuntime
                .openTransportBootstrapRegistrationSetAcknowledgement(
                    from: canonicalEventBytes,
                    proof: proof,
                    authorizationKey: authorizationKey.storage.value,
                    claimSet: claimSet.storage.value,
                    responseSet: responseSet.storage.value,
                    registrationSet: registrationSet.storage.value,
                    conductorAssignments: conductorAssignments.map {
                        $0.storage.value
                    },
                    conductorControlSigningKey:
                        conductorControlSigningKey,
                    currentUnixSeconds: currentUnixSeconds
                )
            return .init(opened, projectDocument: { .init($0) })
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func sealTransportBootstrapRegistrationSetAcknowledgementSet(
        _ acknowledgementSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapRegistrationSetAcknowledgementSet,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        registrationSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistrationSet,
        conductorAssignments: [OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapConductorMailboxAssignment],
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
                    .sealTransportBootstrapRegistrationSetAcknowledgementSet(
                        acknowledgementSet.storage.value,
                        proof: proof,
                        authorizationKey: authorizationKey.storage.value,
                        claimSet: claimSet.storage.value,
                        responseSet: responseSet.storage.value,
                        registrationSet: registrationSet.storage.value,
                        conductorAssignments: conductorAssignments.map {
                            $0.storage.value
                        },
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
    public func openTransportBootstrapRegistrationSetAcknowledgementSet(
        from canonicalEventBytes: Data,
        authorizationKey: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAuthorizationKeyDocument,
        claimSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapControlMailboxClaimSet,
        responseSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapBlindResponseSet,
        registrationSet: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxRegistrationSet,
        localAnonymousMailboxAssignment: OpalBase.Account
            .MosaicPrivateAlphaRuntime
            .TransportBootstrapAnonymousMailboxAssignment?,
        recipientControlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        currentUnixSeconds: UInt64
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapOpenedDocument<OpalBase.Account
            .MosaicPrivateAlphaRuntime
            .TransportBootstrapRegistrationSetAcknowledgementSet> {
        try await performTransportBootstrapDocumentOperation { proof in
            let opened = try FusionRuntime
                .openTransportBootstrapRegistrationSetAcknowledgementSet(
                    from: canonicalEventBytes,
                    proof: proof,
                    authorizationKey: authorizationKey.storage.value,
                    claimSet: claimSet.storage.value,
                    responseSet: responseSet.storage.value,
                    registrationSet: registrationSet.storage.value,
                    localAnonymousMailboxAssignment:
                        localAnonymousMailboxAssignment?.storage.value,
                    recipientControlSigningKey:
                        recipientControlSigningKey,
                    currentUnixSeconds: currentUnixSeconds
                )
            return .init(opened, projectDocument: { .init($0) })
        }
    }
}
#endif
