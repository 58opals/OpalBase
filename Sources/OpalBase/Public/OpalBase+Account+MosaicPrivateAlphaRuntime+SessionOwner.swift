// OpalBase+Account+MosaicPrivateAlphaRuntime+SessionOwner.swift

#if os(macOS)
import Foundation
import OpalCrypto
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime.FreshHost {
    /// Claims the Base-owned facade over this host's sole Fusion owner.
    @_spi(MosaicPrivateAlpha)
    public func makeSessionOwner() async throws -> OpalBase.Account
        .MosaicPrivateAlphaRuntime.SessionOwner {
        try await sessionOwnerClaim.claim()
        return .init(
            binding: binding,
            owner: privateDeploymentOwner,
            transactionHost: transactionHost,
            previousOutputSource: previousOutputSource,
            walletRecoveryOwner: nil
        )
    }
}

extension OpalBase.Account.MosaicPrivateAlphaRuntime.RecoveryOwner {
    /// Claims the Base-owned facade over this recovery bundle's sole Fusion owner.
    @_spi(MosaicPrivateAlpha)
    public func makeSessionOwner() async throws -> OpalBase.Account
        .MosaicPrivateAlphaRuntime.SessionOwner {
        try await sessionOwnerClaim.claim()
        return .init(
            binding: binding,
            owner: privateDeploymentOwner,
            transactionHost: transactionHost,
            previousOutputSource: previousOutputSource,
            walletRecoveryOwner: walletRecoveryOwner
        )
    }
}

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Sole application-facing owner for formation, recovery, and post-manifest execution.
    ///
    /// This actor retains both Base wallet authority and previous-output authority while
    /// keeping every OpalFusion type behind the OpalBase boundary.
    @_spi(MosaicPrivateAlpha)
    public actor SessionOwner {
        typealias FusionRuntime = OpalFusion.MosaicPrivateAlphaRuntime

        @_spi(MosaicPrivateAlpha) public nonisolated let binding: Binding

        let owner: FusionRuntime.Owner
        private let transactionHost:
            any OpalFusion.Host.MosaicCompleteTransactionHost
        private let previousOutputSource:
            OpalBase.Network.TransactionReader
        private let walletRecoveryOwner: OpalBase.Account
            .MosaicPrivateAlphaRecoveryOwner?
        var execution: FusionRuntime.PostManifestExecution?
        var sessionOperationIsInProgress = false
        var constructionIsInProgress = false
        var mustValidateRecoveredTerminal = false
        var protocolTerminalEvidenceWasObserved = false
        var walletTerminalDispositionWasObserved = false

        init(
            binding: Binding,
            owner: FusionRuntime.Owner,
            transactionHost:
                any OpalFusion.Host.MosaicCompleteTransactionHost,
            previousOutputSource: OpalBase.Network.TransactionReader,
            walletRecoveryOwner: OpalBase.Account
                .MosaicPrivateAlphaRecoveryOwner?
        ) {
            self.binding = binding
            self.owner = owner
            self.transactionHost = transactionHost
            self.previousOutputSource = previousOutputSource
            self.walletRecoveryOwner = walletRecoveryOwner
        }

        /// Continues the exact authenticated wallet recovery retained by this recovered session.
        ///
        /// This operation is available only after this owner returns exact terminal Fusion
        /// evidence. Fresh sessions must then cross the durable application-recovery boundary
        /// before calling it. A terminal return proves only the Base-owned wallet disposition;
        /// the application must separately retain both terminal records and complete outer cleanup
        /// before reporting the attempt as cleaned.
        @_spi(MosaicPrivateAlpha)
        public func resumeWalletRecovery() async throws -> Outcome {
            guard protocolTerminalEvidenceWasObserved,
                  let walletRecoveryOwner else {
                throw Failure.invalidRecoveryState
            }
            guard !sessionOperationIsInProgress,
                  !constructionIsInProgress else {
                throw Failure.operationInProgress
            }
            sessionOperationIsInProgress = true
            defer { sessionOperationIsInProgress = false }
            do {
                let outcome = Outcome(
                    try await walletRecoveryOwner.resume()
                )
                if case .terminal = outcome {
                    walletTerminalDispositionWasObserved = true
                }
                return outcome
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch let failure as OpalBase.Account
                .MosaicPrivateAlphaRecoveryOwner.Failure {
                throw Failure(failure)
            } catch {
                throw Failure.invalidRecoveryState
            }
        }

        /// Continues only the complete transaction bytes retained by authenticated wallet recovery.
        @_spi(MosaicPrivateAlpha)
        public func commitRecoveredLocallySignedTransaction(
            transactionBytes: Data
        ) async throws -> Outcome {
            guard protocolTerminalEvidenceWasObserved,
                  let walletRecoveryOwner else {
                throw Failure.invalidRecoveryState
            }
            guard !sessionOperationIsInProgress,
                  !constructionIsInProgress else {
                throw Failure.operationInProgress
            }
            sessionOperationIsInProgress = true
            defer { sessionOperationIsInProgress = false }
            do {
                let transaction = try OpalFusion.Host
                    .MosaicCompleteTransaction(
                        transactionBytes: [UInt8](transactionBytes)
                    )
                let outcome = Outcome(
                    try await walletRecoveryOwner
                        .commitRecoveredLocallySignedTransaction(transaction)
                )
                if case .terminal = outcome {
                    walletTerminalDispositionWasObserved = true
                }
                return outcome
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch let failure as OpalBase.Account
                .MosaicPrivateAlphaRecoveryOwner.Failure {
                throw Failure(failure)
            } catch {
                throw Failure(error)
            }
        }

        /// Persists approval and exact intent before dispatch through one attested chain client.
        @_spi(MosaicPrivateAlpha)
        public func broadcastRecoveredTransaction(
            securityProfile: OpalBase.WalletSecurityProfile,
            using chainClient: ChainClient,
            requestApproval: @escaping @Sendable (
                BroadcastApprovalRequest
            ) async throws -> Bool
        ) async throws -> ChainState {
            guard protocolTerminalEvidenceWasObserved,
                  let walletRecoveryOwner else {
                throw Failure.invalidRecoveryState
            }
            guard !sessionOperationIsInProgress,
                  !constructionIsInProgress else {
                throw Failure.operationInProgress
            }
            sessionOperationIsInProgress = true
            defer { sessionOperationIsInProgress = false }
            do {
                let state = try await walletRecoveryOwner
                    .broadcastRecoveredTransaction(
                        securityProfile: securityProfile,
                        using: chainClient.networkClient,
                        requestApproval: { request in
                            guard let exactRequest = BroadcastApprovalRequest(
                                request
                            ) else {
                                return .rejected
                            }
                            return try await requestApproval(exactRequest)
                                ? .approved : .rejected
                        }
                    )
                return .init(state)
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch let failure as OpalBase.Account
                .MosaicPrivateAlphaRecoveryOwner.Failure {
                throw Failure(failure)
            } catch {
                throw Failure(error)
            }
        }

        /// Records one uncached exact transaction observation through the attested client.
        @_spi(MosaicPrivateAlpha)
        public func reconcileChain(
            using chainClient: ChainClient
        ) async throws -> ChainOutcome {
            guard protocolTerminalEvidenceWasObserved,
                  let walletRecoveryOwner else {
                throw Failure.invalidRecoveryState
            }
            guard !sessionOperationIsInProgress,
                  !constructionIsInProgress else {
                throw Failure.operationInProgress
            }
            sessionOperationIsInProgress = true
            defer { sessionOperationIsInProgress = false }
            do {
                return .init(
                    try await walletRecoveryOwner.reconcileChain(
                        using: chainClient.networkClient
                    )
                )
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch let failure as OpalBase.Account
                .MosaicPrivateAlphaRecoveryOwner.Failure {
                throw Failure(failure)
            } catch {
                throw Failure(error)
            }
        }

        /// Lets app policy finalize only the latest exact confirmed observation.
        @_spi(MosaicPrivateAlpha)
        public func authorizeChainFinality(
            using authorize: @Sendable (ChainState) async throws -> Bool
        ) async throws -> TerminalDisposition {
            guard protocolTerminalEvidenceWasObserved,
                  let walletRecoveryOwner else {
                throw Failure.invalidRecoveryState
            }
            guard !sessionOperationIsInProgress,
                  !constructionIsInProgress else {
                throw Failure.operationInProgress
            }
            sessionOperationIsInProgress = true
            defer { sessionOperationIsInProgress = false }
            do {
                let disposition = TerminalDisposition(
                    try await walletRecoveryOwner
                        .authorizeChainFinality { state in
                            try await authorize(.init(state))
                        }
                )
                walletTerminalDispositionWasObserved = true
                return disposition
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch let failure as OpalBase.Account
                .MosaicPrivateAlphaRecoveryOwner.Failure {
                throw Failure(failure)
            } catch {
                throw Failure(error)
            }
        }

        /// Durably authorizes exact-envelope erasure after this owner observes both terminal proofs.
        @_spi(MosaicPrivateAlpha)
        public func authorizeWalletJournalErasure() async throws
            -> OpalBase.Account.MosaicPrivateAlphaJournal.CleanupRequirement {
            guard protocolTerminalEvidenceWasObserved,
                  walletTerminalDispositionWasObserved,
                  let walletRecoveryOwner else {
                throw Failure.invalidRecoveryState
            }
            guard !sessionOperationIsInProgress,
                  !constructionIsInProgress else {
                throw Failure.operationInProgress
            }
            sessionOperationIsInProgress = true
            defer { sessionOperationIsInProgress = false }
            do {
                return .init(
                    try await walletRecoveryOwner.authorizeJournalErasure()
                )
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch let failure as OpalBase.Account
                .MosaicPrivateAlphaRecoveryOwner.Failure {
                throw Failure(failure)
            } catch {
                throw Failure.invalidRecoveryState
            }
        }

        /// Restores authenticated mailbox state, initializes exact companion journals when
        /// needed, and constructs the contributor execution exactly once.
        @_spi(MosaicPrivateAlpha)
        public func makeContributorExecution(
            mailboxArchive: PostManifestContributorMailboxArchive,
            runtimeCapabilities: PostManifestRuntimeCapabilities,
            recoveryPersistence: FusionRecoveryPersistence,
            privateDeploymentRelays: PrivateDeploymentRelayCapabilities,
            controlSigningKey: OpalCrypto.Secp256k1.SigningKey,
            controlEventSigningKey: OpalCrypto.Secp256k1.SigningKey,
            loadSlotSecrets: @escaping @Sendable (
                Binding,
                PostManifestReservationLease
            ) async throws -> [PostManifestComponentSlotSecrets],
            installOrLoadAuthorizationRecoveryStates:
                @escaping @Sendable (
                    Binding,
                    PostManifestReservationLease,
                    [PostManifestComponentSlotAuthorizationRecoveryState]
                ) async throws
                    -> [PostManifestComponentSlotAuthorizationRecoveryState]
        ) async throws {
            guard execution == nil else {
                throw Failure.invalidRecoveryState
            }
            guard !sessionOperationIsInProgress,
                  !constructionIsInProgress else {
                throw Failure.operationInProgress
            }
            constructionIsInProgress = true
            defer { constructionIsInProgress = false }
            do {
                try await normalizeLoadedOwner(
                    recoveryPersistence: recoveryPersistence,
                    privateDeploymentRelays: privateDeploymentRelays
                )
                let distribution = try await restoreContributorMailboxes(
                    mailboxArchive,
                    currentUnixSeconds:
                        runtimeCapabilities.timing.currentUnixSeconds()
                )
                guard !distribution.isConductor else {
                    throw Failure.invalidRecoveryState
                }
                let capabilities = runtimeCapabilities.fusionCapabilities(
                    mailboxes: distribution.fusionDistribution
                        .mailboxCapabilities
                )
                let construction = try await prepareConstruction(
                    distribution: distribution,
                    capabilities: capabilities,
                    recoveryPersistence: recoveryPersistence
                )
                let binding = binding
                execution = try await construction.makeContributorExecution(
                    host: .init(
                        transactionHost: transactionHost,
                        previousOutputSource: previousOutputSource,
                        controlSigningKey: controlSigningKey,
                        controlEventSigningKey: controlEventSigningKey,
                        loadSlotSecrets: { _, lease in
                            try await loadSlotSecrets(
                                binding,
                                .init(lease)
                            ).map(\.fusionSecrets)
                        },
                        installOrLoadAuthorizationRecoveryStates: {
                            _, lease, candidate in
                            try await installOrLoadAuthorizationRecoveryStates(
                                binding,
                                .init(lease),
                                candidate.map {
                                    .init($0)
                                }
                            ).map(\.fusionRecoveryState)
                        }
                    ),
                    capabilities: capabilities
                )
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch let failure as Failure {
                throw failure
            } catch {
                throw Failure(error)
            }
        }

        /// Restores authenticated mailbox and purpose-separated RSA state, then constructs
        /// the conductor execution exactly once.
        @_spi(MosaicPrivateAlpha)
        public func makeConductorExecution(
            mailboxArchive: PostManifestConductorMailboxArchive,
            runtimeCapabilities: PostManifestRuntimeCapabilities,
            recoveryPersistence: FusionRecoveryPersistence,
            privateDeploymentRelays: PrivateDeploymentRelayCapabilities,
            authorizationKeys: PostManifestConductorAuthorizationKeys,
            controlSigningKey: OpalCrypto.Secp256k1.SigningKey,
            controlEventSigningKey: OpalCrypto.Secp256k1.SigningKey
        ) async throws {
            guard execution == nil else {
                throw Failure.invalidRecoveryState
            }
            guard !sessionOperationIsInProgress,
                  !constructionIsInProgress else {
                throw Failure.operationInProgress
            }
            constructionIsInProgress = true
            defer { constructionIsInProgress = false }
            do {
                try await normalizeLoadedOwner(
                    recoveryPersistence: recoveryPersistence,
                    privateDeploymentRelays: privateDeploymentRelays
                )
                let distribution = try await restoreConductorMailboxes(
                    mailboxArchive,
                    currentUnixSeconds:
                        runtimeCapabilities.timing.currentUnixSeconds()
                )
                guard distribution.isConductor else {
                    throw Failure.invalidRecoveryState
                }
                let capabilities = runtimeCapabilities.fusionCapabilities(
                    mailboxes: distribution.fusionDistribution
                        .mailboxCapabilities
                )
                let construction = try await prepareConstruction(
                    distribution: distribution,
                    capabilities: capabilities,
                    recoveryPersistence: recoveryPersistence
                )
                execution = try await construction.makeConductorExecution(
                    host: .init(
                        componentAuthorizationSecurityKey:
                            authorizationKeys.component,
                        bchSignatureAuthorizationSecurityKey:
                            authorizationKeys.bchSignature,
                        previousOutputSource: previousOutputSource,
                        controlSigningKey: controlSigningKey,
                        controlEventSigningKey: controlEventSigningKey
                    ),
                    capabilities: capabilities
                )
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch let failure as Failure {
                throw failure
            } catch {
                throw Failure(error)
            }
        }

        @_spi(MosaicPrivateAlpha)
        public func start() async throws {
            guard let execution else { throw Failure.invalidRecoveryState }
            do {
                try await execution.start()
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw Failure(error)
            }
        }

        @_spi(MosaicPrivateAlpha)
        public func acceptReceivedAbort(
            _ event: PrivateDeploymentEvent
        ) async throws {
            guard let execution else { throw Failure.invalidRecoveryState }
            do {
                try await execution.acceptReceivedAbort(event.fusionEvent)
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw Failure(error)
            }
        }

        @_spi(MosaicPrivateAlpha)
        public func acceptReceivedCompletion(
            _ event: PrivateDeploymentEvent
        ) async throws {
            guard let execution else { throw Failure.invalidRecoveryState }
            do {
                try await execution.acceptReceivedCompletion(
                    event.fusionEvent
                )
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw Failure(error)
            }
        }

        @_spi(MosaicPrivateAlpha)
        public func requestTimeoutAbort(
            currentUnixSeconds: UInt64,
            signing: PrivateDeploymentSigningMaterial
        ) async throws {
            guard let execution else { throw Failure.invalidRecoveryState }
            do {
                try await execution.requestTimeoutAbort(
                    currentUnixSeconds: currentUnixSeconds,
                    signing: try await signing.claimFusionCapability()
                )
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw Failure(error)
            }
        }

        @_spi(MosaicPrivateAlpha)
        public func stop() async {
            await execution?.stop()
        }

        /// Claims one runtime termination. Non-protocol failures remain recovery-required;
        /// only package-authenticated completion or abort can mint cleanup evidence.
        @_spi(MosaicPrivateAlpha)
        public func waitForDisposition(
            createdAtUnixSeconds: UInt64,
            signing: PrivateDeploymentSigningMaterial?,
            recoveryPersistence: FusionRecoveryPersistence,
            privateDeploymentRelays: PrivateDeploymentRelayCapabilities
        ) async throws -> Disposition {
            guard let execution else { throw Failure.invalidRecoveryState }
            do {
                guard let termination = try await execution
                    .waitForTermination() else {
                    return .alreadyClaimed
                }
                let reference = termination.reservationReference.map(
                    PostManifestReservationReference.init
                )
                switch termination.kind {
                case .recoveryRequired:
                    return .recoveryRequired(
                        .walletState,
                        reservationReference: reference
                    )
                case .failed:
                    return .recoveryRequired(
                        .runtimeFailure,
                        reservationReference: reference
                    )
                case .transportFailed:
                    return .recoveryRequired(
                        .transportUnavailable,
                        reservationReference: reference
                    )
                case .completed, .aborted:
                    break
                }

                let step: FusionRuntime.Step
                if mustValidateRecoveredTerminal {
                    step = try await owner
                        .validateRecoveredPostManifestTerminal(
                            consuming: termination
                        )
                    mustValidateRecoveredTerminal = false
                } else if let signing {
                    step = try await owner.preparePostManifestTermination(
                        consuming: termination,
                        createdAtUnixSeconds: createdAtUnixSeconds,
                        signing: try await signing.claimFusionCapability()
                    )
                } else {
                    step = try await owner.preparePostManifestTermination(
                        consuming: termination,
                        createdAtUnixSeconds: createdAtUnixSeconds,
                        signing: nil
                    )
                }
                return try await finishTerminalStep(
                    step,
                    recoveryPersistence: recoveryPersistence,
                    privateDeploymentRelays: privateDeploymentRelays
                )
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch let failure as Failure {
                throw failure
            } catch {
                throw Failure(error)
            }
        }

        private func prepareConstruction(
            distribution: PostManifestMailboxDistribution,
            capabilities: FusionRuntime.PostManifestRuntimeCapabilities,
            recoveryPersistence: FusionRecoveryPersistence
        ) async throws -> FusionRuntime.PostManifestConstruction {
            guard distribution.binding == binding,
                  distribution.localControlIdentity.count == 32 else {
                throw Failure.invalidBinding
            }
            do {
                let step = try await owner.preparePostManifestRuntime(
                    localControlIdentity:
                        distribution.localControlIdentity,
                    capabilities: capabilities
                )
                let next = try await persistOnlyStep(
                    step,
                    recoveryPersistence: recoveryPersistence
                )
                guard case .awaitingInput = next else {
                    throw Failure.invalidRecoveryState
                }
            } catch FusionRuntime.Failure.invalidStateTransition {
                // An already initialized recovery proceeds directly to the
                // one-use construction. Every other invalid state is rejected
                // again by the construction guard without journal mutation.
            }
            return try await owner.makePostManifestConstruction(
                localControlIdentity: distribution.localControlIdentity
            )
        }

        private func normalizeLoadedOwner(
            recoveryPersistence: FusionRecoveryPersistence,
            privateDeploymentRelays: PrivateDeploymentRelayCapabilities
        ) async throws {
            var step = try await owner.nextStep()
            while true {
                switch step {
                case let .persist(transition):
                    step = try await persist(
                        transition,
                        recoveryPersistence: recoveryPersistence
                    )
                case let .publishPrivateDeployment(publication):
                    step = try await publish(
                        publication,
                        privateDeploymentRelays: privateDeploymentRelays
                    )
                case let .recover(directive):
                    switch directive {
                    case let .resumePrivateDeployment(continuation):
                        step = try await owner.resumePrivateDeployment(
                            continuation
                        )
                    case let .validatePostManifestTerminal(continuation):
                        mustValidateRecoveredTerminal = true
                        step = try await owner.resumePrivateDeployment(
                            continuation
                        )
                    case let .publishPrivateDeployment(publication):
                        step = try await publish(
                            publication,
                            privateDeploymentRelays:
                                privateDeploymentRelays
                        )
                    case .terminal:
                        throw Failure.terminalDispositionRequired
                    }
                case .awaitingInput:
                    return
                case .ignoredDuplicate,
                     .awaitingPreManifestAbortSignature:
                    throw Failure.invalidRecoveryState
                case .terminal:
                    throw Failure.terminalDispositionRequired
                }
            }
        }

        private func persistOnlyStep(
            _ step: FusionRuntime.Step,
            recoveryPersistence: FusionRecoveryPersistence
        ) async throws -> FusionRuntime.Step {
            guard case let .persist(transition) = step else {
                throw Failure.invalidRecoveryState
            }
            return try await persist(
                transition,
                recoveryPersistence: recoveryPersistence
            )
        }

        func persist(
            _ transition: FusionRuntime.RecoveryTransition,
            recoveryPersistence: FusionRecoveryPersistence
        ) async throws -> FusionRuntime.Step {
            let readback = try await recoveryPersistence.persist(
                .init(transition)
            )
            return try await owner.acknowledgePersistence(
                transition,
                exactReadback: readback
            )
        }

        func publish(
            _ publication: consuming FusionRuntime
                .PrivateDeploymentPublication,
            privateDeploymentRelays: PrivateDeploymentRelayCapabilities
        ) async throws -> FusionRuntime.Step {
            let receipt = try await publication.publish(
                using: privateDeploymentRelays.fusionCapabilities()
            )
            return try await owner.acknowledgePrivateDeploymentPublication(
                consuming: receipt
            )
        }

        private func finishTerminalStep(
            _ initial: FusionRuntime.Step,
            recoveryPersistence: FusionRecoveryPersistence,
            privateDeploymentRelays: PrivateDeploymentRelayCapabilities
        ) async throws -> Disposition {
            var step = initial
            while true {
                switch step {
                case let .persist(transition):
                    step = try await persist(
                        transition,
                        recoveryPersistence: recoveryPersistence
                    )
                case let .publishPrivateDeployment(publication):
                    step = try await publish(
                        publication,
                        privateDeploymentRelays: privateDeploymentRelays
                    )
                case let .recover(.publishPrivateDeployment(publication)):
                    step = try await publish(
                        publication,
                        privateDeploymentRelays: privateDeploymentRelays
                    )
                case let .recover(.terminal(disposition)),
                     let .terminal(disposition):
                    return .terminal(
                        try await claimTerminalEvidence(disposition)
                    )
                case .recover,
                     .ignoredDuplicate,
                     .awaitingPreManifestAbortSignature,
                     .awaitingInput:
                    throw Failure.invalidRecoveryState
                }
            }
        }

        func claimTerminalEvidence(
            _ disposition: FusionRuntime.TerminalDisposition
        ) async throws -> TerminalEvidence {
            guard case let .cleanupAuthorized(
                reason,
                evidenceIdentifier,
                recoveryRevision
            ) = disposition else {
                throw Failure.invalidRecoveryState
            }
            let evidence = try await owner.claimTerminalEvidence()
            guard evidence.evidenceIdentifier == evidenceIdentifier,
                  evidence.recoveryRevision == recoveryRevision,
                  Binding(evidence.binding) == binding else {
                throw Failure.invalidRecoveryState
            }
            protocolTerminalEvidenceWasObserved = true
            return .init(
                binding: binding,
                reason: .init(reason),
                evidenceIdentifier: evidence.evidenceIdentifier,
                recoveryRevision: evidence.recoveryRevision,
                recoverySnapshotDigest: evidence.recoverySnapshotDigest
            )
        }

        private func restoreContributorMailboxes(
            _ archive: PostManifestContributorMailboxArchive,
            currentUnixSeconds: UInt64
        ) async throws -> PostManifestMailboxDistribution {
            let proof = try await owner
                .makePostManifestExecutionPrivateDeploymentProof()
            let documents = try Self.loadCommonMailboxDocuments(
                archive.documents,
                proof: proof,
                currentUnixSeconds: currentUnixSeconds
            )
            let registration = try FusionRuntime
                .loadTransportBootstrapAnonymousMailboxRegistration(
                    from: archive.registration,
                    proof: proof,
                    authorizationKey: documents.authorizationKey,
                    claimSet: documents.claimSet,
                    responseSet: documents.responseSet,
                    currentUnixSeconds: currentUnixSeconds
                )
            let assignment = try FusionRuntime
                .loadTransportBootstrapAnonymousMailboxAssignment(
                    from: archive.assignment,
                    proof: proof,
                    authorizationKey: documents.authorizationKey,
                    claimSet: documents.claimSet,
                    responseSet: documents.responseSet,
                    registration: registration,
                    currentUnixSeconds: currentUnixSeconds
                )
            let distribution = try FusionRuntime
                .makeContributorTransportBootstrapMailboxDistribution(
                    proof: proof,
                    authorizationKey: documents.authorizationKey,
                    claimSet: documents.claimSet,
                    responseSet: documents.responseSet,
                    registration: registration,
                    assignment: assignment,
                    registrationSet: documents.registrationSet,
                    acknowledgementSet: documents.acknowledgementSet,
                    contributorControlIdentity:
                        archive.contributorControlIdentity,
                    localControlRecipientSigningKey:
                        archive.localControlRecipientSigningKey,
                    currentUnixSeconds: currentUnixSeconds
                )
            return .init(
                binding: binding,
                localControlIdentity:
                    archive.contributorControlIdentity,
                isConductor: false,
                distribution: distribution
            )
        }

        private func restoreConductorMailboxes(
            _ archive: PostManifestConductorMailboxArchive,
            currentUnixSeconds: UInt64
        ) async throws -> PostManifestMailboxDistribution {
            let proof = try await owner
                .makePostManifestExecutionPrivateDeploymentProof()
            let documents = try Self.loadCommonMailboxDocuments(
                archive.documents,
                proof: proof,
                currentUnixSeconds: currentUnixSeconds
            )
            var registrations: [
                FusionRuntime.TransportBootstrapAnonymousMailboxRegistration
            ] = []
            var assignments: [
                FusionRuntime.TransportBootstrapConductorMailboxAssignment
            ] = []
            for archiveAssignment in archive.assignments {
                let registration = try FusionRuntime
                    .loadTransportBootstrapAnonymousMailboxRegistration(
                        from: archiveAssignment.registration,
                        proof: proof,
                        authorizationKey: documents.authorizationKey,
                        claimSet: documents.claimSet,
                        responseSet: documents.responseSet,
                        currentUnixSeconds: currentUnixSeconds
                    )
                registrations.append(registration)
                assignments.append(
                    try FusionRuntime
                        .restoreTransportBootstrapConductorMailboxAssignment(
                            from: archiveAssignment.assignment,
                            proof: proof,
                            authorizationKey: documents.authorizationKey,
                            claimSet: documents.claimSet,
                            responseSet: documents.responseSet,
                            registration: registration,
                            recipientPrivateKeys:
                                archiveAssignment.recipientPrivateKeys,
                            currentUnixSeconds: currentUnixSeconds
                        )
                )
            }
            let distribution = try FusionRuntime
                .makeConductorTransportBootstrapMailboxDistribution(
                    proof: proof,
                    authorizationKey: documents.authorizationKey,
                    claimSet: documents.claimSet,
                    responseSet: documents.responseSet,
                    registrations: registrations,
                    conductorAssignments: assignments,
                    registrationSet: documents.registrationSet,
                    acknowledgementSet: documents.acknowledgementSet,
                    localControlRecipientSigningKey:
                        archive.localControlRecipientSigningKey,
                    currentUnixSeconds: currentUnixSeconds
                )
            let localVerificationKey = archive
                .localControlRecipientSigningKey
                .bip340VerificationKey
            guard let localControlIdentity = distribution
                .mailboxCapabilities.controlMailboxes.first(where: {
                    $0.eventVerificationKey == localVerificationKey
                })?.controlIdentity else {
                throw Failure.invalidBinding
            }
            return .init(
                binding: binding,
                localControlIdentity: localControlIdentity,
                isConductor: true,
                distribution: distribution
            )
        }

        static func loadCommonMailboxDocuments(
            _ archive: PostManifestMailboxDocuments,
            proof: FusionRuntime.PrivateDeploymentProof,
            currentUnixSeconds: UInt64
        ) throws -> (
            authorizationKey:
                FusionRuntime.TransportBootstrapAuthorizationKeyDocument,
            claimSet: FusionRuntime.TransportBootstrapControlMailboxClaimSet,
            responseSet: FusionRuntime.TransportBootstrapBlindResponseSet,
            registrationSet: FusionRuntime
                .TransportBootstrapAnonymousMailboxRegistrationSet,
            acknowledgementSet: FusionRuntime
                .TransportBootstrapRegistrationSetAcknowledgementSet
        ) {
            let authorizationKey = try FusionRuntime
                .loadTransportBootstrapAuthorizationKeyDocument(
                    from: archive.authorizationKey,
                    proof: proof,
                    currentUnixSeconds: currentUnixSeconds
                )
            let claimSet = try FusionRuntime
                .loadTransportBootstrapControlMailboxClaimSet(
                    from: archive.controlClaimSet,
                    proof: proof,
                    authorizationKey: authorizationKey,
                    currentUnixSeconds: currentUnixSeconds
                )
            let responseSet = try FusionRuntime
                .loadTransportBootstrapBlindResponseSet(
                    from: archive.blindResponseSet,
                    proof: proof,
                    authorizationKey: authorizationKey,
                    claimSet: claimSet,
                    currentUnixSeconds: currentUnixSeconds
                )
            let registrationSet = try FusionRuntime
                .loadTransportBootstrapAnonymousMailboxRegistrationSet(
                    from: archive.registrationSet,
                    proof: proof,
                    authorizationKey: authorizationKey,
                    claimSet: claimSet,
                    responseSet: responseSet,
                    currentUnixSeconds: currentUnixSeconds
                )
            let acknowledgementSet = try FusionRuntime
                .loadTransportBootstrapRegistrationSetAcknowledgementSet(
                    from: archive.acknowledgementSet,
                    proof: proof,
                    authorizationKey: authorizationKey,
                    claimSet: claimSet,
                    responseSet: responseSet,
                    registrationSet: registrationSet,
                    currentUnixSeconds: currentUnixSeconds
                )
            return (
                authorizationKey,
                claimSet,
                responseSet,
                registrationSet,
                acknowledgementSet
            )
        }
    }
}
#endif
