// OpalBase+Account+MosaicPrivateAlphaRuntime+SessionOwner+PrivateDeployment.swift

#if os(macOS)
import Foundation
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime.SessionOwner {
    /// Persists the fresh Fusion snapshot, installs the authenticated discovery context,
    /// and returns only after the resulting snapshot is durably read back.
    @_spi(MosaicPrivateAlpha)
    public func beginPrivateDeployment(
        opaquePoolDocument: Data,
        relaySetDocument: Data,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try claimPrivateDeploymentOperation()
        defer { releasePrivateDeploymentOperation() }
        do {
            let initial = try await advancePrivateDeploymentStep(
                try await owner.nextStep(),
                capabilities: capabilities
            )
            guard initial == .awaitingInput(.discovery) else {
                throw OpalBase.Account.MosaicPrivateAlphaRuntime.Failure
                    .invalidRecoveryState
            }
            return try await advancePrivateDeploymentStep(
                try await owner.installPrivateDeploymentContext(
                    opaquePoolDocument: opaquePoolDocument,
                    relaySetDocument: relaySetDocument
                ),
                capabilities: capabilities
            )
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch let failure
            as OpalBase.Account.MosaicPrivateAlphaRuntime.Failure
        {
            throw failure
        } catch {
            throw OpalBase.Account.MosaicPrivateAlphaRuntime.Failure(error)
        }
    }

    /// Resumes an exact authenticated Fusion snapshot through its required recovery directive.
    @_spi(MosaicPrivateAlpha)
    public func resumePrivateDeployment(
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.nextStep()
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func prepareAvailabilityBeacon(
        proofOfWorkNonce: UInt64,
        createdAtUnixSeconds: UInt64,
        signing: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningMaterial,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.prepareAvailabilityBeacon(
                proofOfWorkNonce: proofOfWorkNonce,
                createdAtUnixSeconds: createdAtUnixSeconds,
                signing: try await signing.claimFusionCapability()
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func acceptAvailabilityBeacon(
        _ event: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.acceptAvailabilityBeacon(event.fusionEvent)
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func completeDiscovery(
        currentUnixSeconds: UInt64,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.completeDiscovery(
                currentUnixSeconds: currentUnixSeconds
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func prepareCandidateSetAcknowledgement(
        createdAtUnixSeconds: UInt64,
        signing: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningMaterial,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.prepareCandidateSetAcknowledgement(
                createdAtUnixSeconds: createdAtUnixSeconds,
                signing: try await signing.claimFusionCapability()
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func acceptCandidateSetAcknowledgement(
        _ event: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.acceptCandidateSetAcknowledgement(
                event.fusionEvent
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func completeCandidateSetAgreement(
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.completeCandidateSetAgreement()
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func prepareCandidateAdmission(
        createdAtUnixSeconds: UInt64,
        discoverySigning: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningMaterial,
        controlSigning: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningMaterial,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.prepareCandidateAdmission(
                createdAtUnixSeconds: createdAtUnixSeconds,
                discoverySigning:
                    try await discoverySigning.claimFusionCapability(),
                controlSigning: try await controlSigning.claimFusionCapability()
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func acceptCandidateAdmission(
        _ event: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.acceptCandidateAdmission(event.fusionEvent)
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func completeCandidateAdmission(
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.completeCandidateAdmission()
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func prepareRoleCommitment(
        randomness: Data,
        createdAtUnixSeconds: UInt64,
        signing: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningMaterial,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.prepareRoleCommitment(
                randomness: randomness,
                createdAtUnixSeconds: createdAtUnixSeconds,
                signing: try await signing.claimFusionCapability()
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func acceptRoleCommitment(
        _ event: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.acceptRoleCommitment(event.fusionEvent)
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func completeRoleCommitments(
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.completeRoleCommitments()
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func prepareRoleReveal(
        randomness: Data,
        createdAtUnixSeconds: UInt64,
        signing: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningMaterial,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.prepareRoleReveal(
                randomness: randomness,
                createdAtUnixSeconds: createdAtUnixSeconds,
                signing: try await signing.claimFusionCapability()
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func acceptRoleReveal(
        _ event: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.acceptRoleReveal(event.fusionEvent)
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func completeRoleElection(
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.completeRoleElection()
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func prepareContributorNonceAllocation(
        publicSources: [Data],
        createdAtUnixSeconds: UInt64,
        signing: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningMaterial,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.prepareContributorNonceAllocation(
                publicSources: publicSources,
                createdAtUnixSeconds: createdAtUnixSeconds,
                signing: try await signing.claimFusionCapability()
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func acceptContributorNonceAllocation(
        _ event: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.acceptContributorNonceAllocation(
                event.fusionEvent
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func completeNonceAllocation(
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.completeNonceAllocation()
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func prepareManifestProposal(
        authorizationKeys: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentManifestAuthorizationKeys,
        createdAtUnixSeconds: UInt64,
        signing: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningMaterial,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.prepareManifestProposal(
                authorizationKeys: authorizationKeys.fusionKeys,
                createdAtUnixSeconds: createdAtUnixSeconds,
                signing: try await signing.claimFusionCapability()
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func acceptManifestProposal(
        _ event: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.acceptManifestProposal(event.fusionEvent)
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func prepareManifestSignature(
        createdAtUnixSeconds: UInt64,
        signing: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningMaterial,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.prepareManifestSignature(
                createdAtUnixSeconds: createdAtUnixSeconds,
                signing: try await signing.claimFusionCapability()
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func acceptManifestSignature(
        _ event: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.acceptManifestSignature(event.fusionEvent)
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func completeManifestAgreement(
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.completeManifestAgreement()
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func preparePreManifestAbort(
        currentUnixSeconds: UInt64,
        signing: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningMaterial,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.preparePreManifestAbort(
                currentUnixSeconds: currentUnixSeconds,
                signing: try await signing.claimFusionCapability()
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func acceptReceivedPreManifestAbort(
        _ event: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try await performPrivateDeploymentOperation(
            capabilities: capabilities
        ) {
            try await owner.acceptReceivedPreManifestAbort(
                event.fusionEvent
            )
        }
    }

    private func performPrivateDeploymentOperation(
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities,
        _ operation: () async throws -> FusionRuntime.Step
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        try claimPrivateDeploymentOperation()
        defer { releasePrivateDeploymentOperation() }
        do {
            return try await advancePrivateDeploymentStep(
                try await operation(),
                capabilities: capabilities
            )
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch let failure
            as OpalBase.Account.MosaicPrivateAlphaRuntime.Failure
        {
            throw failure
        } catch {
            throw OpalBase.Account.MosaicPrivateAlphaRuntime.Failure(error)
        }
    }

    private func claimPrivateDeploymentOperation() throws {
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
    }

    private func releasePrivateDeploymentOperation() {
        sessionOperationIsInProgress = false
    }

    private func advancePrivateDeploymentStep(
        _ initial: FusionRuntime.Step,
        capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .PrivateDeploymentCapabilities
    ) async throws
        -> OpalBase.Account.MosaicPrivateAlphaRuntime.PrivateDeploymentProgress
    {
        var step = initial
        while true {
            switch step {
            case .persist(let transition):
                step = try await persist(
                    transition,
                    recoveryPersistence: capabilities.recoveryPersistence
                )
            case .publishPrivateDeployment(let publication):
                step = try await publish(
                    publication,
                    privateDeploymentRelays: capabilities.relays
                )
            case .recover(let directive):
                switch directive {
                case .resumePrivateDeployment(let continuation):
                    step = try await owner.resumePrivateDeployment(
                        continuation
                    )
                case .validatePostManifestTerminal(let continuation):
                    mustValidateRecoveredTerminal = true
                    step = try await owner.resumePrivateDeployment(
                        continuation
                    )
                case .publishPrivateDeployment(let publication):
                    step = try await publish(
                        publication,
                        privateDeploymentRelays: capabilities.relays
                    )
                case .terminal(let disposition):
                    return .terminal(
                        try await claimTerminalEvidence(disposition)
                    )
                }
            case .ignoredDuplicate(let phase):
                return .ignoredDuplicate(.init(phase))
            case .awaitingPreManifestAbortSignature(let phase):
                return .awaitingAbortSignature(.init(phase))
            case .awaitingInput(let phase):
                return .awaitingInput(.init(phase))
            case .terminal(let disposition):
                return .terminal(
                    try await claimTerminalEvidence(disposition)
                )
            }
        }
    }
}
#endif
