// AccountMosaicPrivateAlphaSessionOwnerChainValidator.swift

#if os(macOS)
import Foundation
import OpalCrypto
@_spi(MosaicPrivateAlpha) import OpalFusion
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalBase

@Suite("OpalBase.Account Mosaic session-owner chain recovery", .tags(.unit, .wallet))
struct AccountMosaicPrivateAlphaSessionOwnerChainValidator {
    typealias Runtime = OpalBase.Account.MosaicPrivateAlphaRuntime

    @Test("Sole session owner guards approval, dispatch, reconciliation, finality, and cleanup")
    func recoverThroughChainFinality() async throws {
        let journalProbe = MosaicAttemptJournalProbeActor(
            authorizesErasure: true
        )
        let prepared = try await makeCommittedAttempt(
            journalProbe: journalProbe,
            profile: .opalMainnetAlpha,
            network: .mainnet
        )
        let packageBinding = await prepared.fixture.host.attemptBinding
        let binding = try #require(Runtime.Binding(
            attemptIdentifier: packageBinding.attemptIdentifier,
            generationIdentifier: packageBinding.generationIdentifier,
            materialIdentifier: packageBinding.materialIdentifier
        ))
        let fusionPersistence = SessionChainFusionPersistenceProbe(
            snapshot: try await makeInitialFusionSnapshot(
                binding: OpalFusion.MosaicPrivateAlphaRuntime.Binding(
                    attemptIdentifier: binding.attemptIdentifier,
                    generationIdentifier: binding.generationIdentifier,
                    materialIdentifier: binding.materialIdentifier
                )
            )
        )
        let transactionReader = OpalBase.Network.TransactionReader(
            fetchRawTransaction: { _ in Data() }
        )
        let recovery = try await Runtime.loadApplicationSessionRecovery(
            account: prepared.fixture.account,
            binding: binding,
            expectedWalletReservationIdentifier:
                packageBinding.walletReservationReference.identifier,
            expectedWalletGeneration:
                packageBinding.walletReservationReference.generation,
            transactionReader: transactionReader,
            fusionRecoverySnapshot: await fusionPersistence.readSnapshot(),
            journalKey: await journalProbe.readFieldDerivedJournalKey(),
            journalScope: await journalProbe.readApplicationScope(),
            journalPersistence: journalProbe.makeApplicationPersistence()
        )
        let owner: Runtime.SessionOwner
        switch consume recovery {
        case let .loadedSessionOwner(value):
            owner = value
        case .abandonedFreshAttempt:
            Issue.record("Expected exact application recovery")
            return
        }

        let relayProbe = MosaicPrivateDeploymentRelayProbe()
        let capabilities = Runtime.PrivateDeploymentCapabilities(
            recoveryPersistence: .init { transition in
                try await fusionPersistence.persist(transition)
            },
            relays: .init(provisionRoutes: { request in
                try await relayProbe.provisionRoutes(for: request)
            })
        )
        #expect(
            try await owner.resumePrivateDeployment(
                capabilities: capabilities
            ) == .awaitingInput(.discovery)
        )
        let documents = try MosaicPrivateDeploymentDocumentFixture.make()
        #expect(
            try await owner.beginPrivateDeployment(
                opaquePoolDocument: documents.opaquePoolDocument,
                relaySetDocument: documents.relaySetDocument,
                capabilities: capabilities
            ) == .awaitingInput(.discovery)
        )
        let beaconSigning = Runtime.PrivateDeploymentSigningMaterial(
            signingKey: try .init(
                rawRepresentation:
                    Data(repeating: 0, count: 31) + Data([1])
            ),
            documentAuxiliaryRandomness: try .init(
                rawRepresentation: Data(repeating: 0xa5, count: 32)
            ),
            eventAuxiliaryRandomness: try .init(
                rawRepresentation: Data(repeating: 0x20, count: 32)
            )
        )
        #expect(
            try await owner.prepareAvailabilityBeacon(
                proofOfWorkNonce: 988_699,
                createdAtUnixSeconds: 1_800_000_001,
                signing: beaconSigning,
                capabilities: capabilities
            ) == .awaitingInput(.discovery)
        )
        let signing = Runtime.PrivateDeploymentSigningMaterial(
            signingKey: try .init(
                rawRepresentation:
                    Data(repeating: 0, count: 31) + Data([1])
            ),
            documentAuxiliaryRandomness: try .init(
                rawRepresentation: Data(repeating: 0xa7, count: 32)
            ),
            eventAuxiliaryRandomness: try .init(
                rawRepresentation: Data(repeating: 0x22, count: 32)
            )
        )
        guard case .terminal = try await owner.preparePreManifestAbort(
            currentUnixSeconds: 1_800_000_060,
            signing: signing,
            capabilities: capabilities
        ) else {
            Issue.record("Expected exact protocol terminal evidence")
            return
        }
        guard case .broadcastApprovalRequired = try await owner
            .resumeWalletRecovery() else {
            Issue.record("Expected guarded broadcast approval")
            return
        }

        let approvalProbe = SessionChainApprovalProbe()
        let broadcastProbe = MosaicBroadcastProbeActor(
            journalProbe: journalProbe
        )
        let broadcastClient = makeChainClient(
            broadcastProbe.makeClient(testingNetwork: .mainnet)
        )
        let chainState = try await owner.broadcastRecoveredTransaction(
            securityProfile: .init(
                secretPersistencePolicy: .acceptProviderOutput,
                networkAccess: .publicChainSyncAndBroadcast,
                signingAccess: .inProcess
            ),
            using: broadcastClient,
            requestApproval: { request in
                await approvalProbe.approve(request)
            }
        )
        let approval = try #require(await approvalProbe.readRequest())
        #expect(approval.profile == .opalMainnetAlpha)
        #expect(approval.network == .mainnet)
        #expect(chainState.transactionHash == approval.transactionHash.naturalOrder)
        #expect(await broadcastProbe.readBroadcasts().count == 1)
        #expect(await broadcastProbe.readObservedPersistedIntent())

        let blockHash = Data(repeating: 0x91, count: 32)
        let confirmedClient = try makeConfirmedChainClient(
            approval: approval,
            blockHash: blockHash,
            confirmations: 6
        )
        guard case let .observed(observed) = try await owner.reconcileChain(
            using: confirmedClient
        ) else {
            Issue.record("Expected an exact confirmed observation")
            return
        }
        #expect(
            observed.latestPresence
                == .present(blockHash: blockHash, confirmations: 6)
        )
        let terminal = try await owner.authorizeChainFinality { state in
            state == observed && state.holdReason == nil
        }
        #expect(
            terminal == .chainFinalized(
                transactionHash: approval.transactionHash.naturalOrder,
                blockHash: blockHash,
                confirmations: 6
            )
        )
        _ = try await owner.authorizeWalletJournalErasure()
    }

    private func makeInitialFusionSnapshot(
        binding: OpalFusion.MosaicPrivateAlphaRuntime.Binding
    ) async throws -> Data {
        let attempt = try OpalFusion.MosaicPrivateAlphaRuntime
            .createFreshAttempt(
                boundTo: binding,
                discoveryEpochStartUnixSeconds: 1_800_000_000
            )
        let owner = try OpalFusion.MosaicPrivateAlphaRuntime.Owner(
            claiming: attempt
        )
        guard case let .persist(transition) = try await owner.nextStep()
        else {
            throw Runtime.Failure.invalidRecoveryState
        }
        return transition.replacementSnapshot
    }

    private func makeChainClient(
        _ client: OpalBase.Account.MosaicNetworkAttestedTransactionClient
    ) -> Runtime.ChainClient {
        Runtime.ChainClient(
            attestation: .init(
                network: .mainnet,
                genesisHash: Data(
                    OpalBase.Network.Environment.mainnet.mosaicGenesisHash
                ),
                serverURLs: [URL(string: "wss://fulcrum.example:50004")!]
            ),
            networkClient: client
        )
    }

    private func makeConfirmedChainClient(
        approval: Runtime.BroadcastApprovalRequest,
        blockHash: Data,
        confirmations: UInt32
    ) throws -> Runtime.ChainClient {
        let decoded = try OpalBase.Transaction.decode(
            from: approval.transactionBytes
        )
        let detail = OpalBase.Transaction.Detail(
            transaction: decoded.transaction,
            blockHash: blockHash,
            blockTime: 1_900_000_000,
            confirmations: confirmations,
            hash: approval.transactionHash,
            rawTransactionData: approval.transactionBytes,
            size: approval.transactionSizeBytes,
            time: nil
        )
        let client = OpalBase.Account.MosaicNetworkAttestedTransactionClient(
            testingNetwork: .mainnet,
            transactionClient: .init(
                broadcastTransaction: { _ in
                    approval.transactionHash.reverseOrder.hexadecimalString
                },
                fetchConfirmations: { _ in UInt(confirmations) },
                fetchConfirmationStatus: { hash in
                    .init(
                        transactionHash: hash,
                        transactionHeight: nil,
                        tipHeight: UInt64(confirmations),
                        confirmations: UInt(confirmations)
                    )
                }
            ),
            fetchFreshDetailedTransaction: { _ in detail }
        )
        return makeChainClient(client)
    }
}

private actor SessionChainApprovalProbe {
    typealias Request = OpalBase.Account.MosaicPrivateAlphaRuntime
        .BroadcastApprovalRequest

    private var request: Request?

    func approve(_ request: Request) -> Bool {
        self.request = request
        return true
    }

    func readRequest() -> Request? {
        request
    }
}

private actor SessionChainFusionPersistenceProbe {
    typealias Transition = OpalBase.Account.MosaicPrivateAlphaRuntime
        .FusionRecoveryTransition

    private var snapshot: Data

    init(snapshot: Data) {
        self.snapshot = Data(snapshot)
    }

    func persist(_ transition: Transition) throws -> Data {
        guard transition.expectedSnapshot == snapshot else {
            throw OpalBase.Account.MosaicPrivateAlphaRuntime.Failure
                .invalidRecoveryState
        }
        snapshot = transition.replacementSnapshot
        return snapshot
    }

    func readSnapshot() -> Data {
        snapshot
    }
}
#endif
