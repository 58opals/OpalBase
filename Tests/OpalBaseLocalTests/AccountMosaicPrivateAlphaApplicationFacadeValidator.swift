// AccountMosaicPrivateAlphaApplicationFacadeValidator.swift

#if os(macOS)
import Foundation
import OpalCrypto
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalBase

@Suite("OpalBase.Account Mosaic application facade", .tags(.unit, .wallet))
struct AccountMosaicPrivateAlphaApplicationFacadeValidator {
    typealias Runtime = OpalBase.Account.MosaicPrivateAlphaRuntime

    @Test("App-only import creates the exact fresh owner and retains its binding")
    func createFreshOwnerWithoutImportingFusion() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 100_000,
            usage: .change,
            hashByte: 0xd1
        )
        let journalProbe = MosaicAttemptJournalProbeActor()
        let journalAttempt = OpalBase.Account.MosaicPrivateAlphaJournal
            .FreshAttempt(try await journalProbe.makeFreshAttempt())
        let binding = try #require(Runtime.Binding(
            attemptIdentifier: Data(repeating: 0x11, count: 32),
            generationIdentifier: Data(repeating: 0x22, count: 32),
            materialIdentifier: Data(repeating: 0x33, count: 32)
        ))
        let walletIdentifier = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-0000000000d1")
        )

        let host = try await Runtime.createFreshApplicationHost(
            account: account,
            binding: binding,
            discoveryEpochStartUnixSeconds: 1_800_000_000,
            walletReservationIdentifier: walletIdentifier,
            walletGeneration: 42,
            selectedInputs: [selectedInput],
            outputAmountsSatoshis: [99_823],
            transactionReader: .init(
                fetchRawTransaction: { _ in Data() }
            ),
            journalAttempt: journalAttempt
        )

        #expect(host.binding == binding)
        let sessionOwner = try await host.makeSessionOwner()
        #expect(sessionOwner.binding == binding)
        await #expect(
            throws: Runtime.Failure.oneTimeCapabilityAlreadyClaimed
        ) {
            _ = try await host.makeSessionOwner()
        }
        guard case let .attemptBinding(recorded) =
            await journalProbe.readRecords().first else {
            Issue.record("Expected one durable Base binding")
            return
        }
        #expect(recorded.attemptIdentifier == binding.attemptIdentifier)
        #expect(
            recorded.generationIdentifier == binding.generationIdentifier
        )
        #expect(recorded.materialIdentifier == binding.materialIdentifier)
        #expect(
            recorded.walletReservationReference.identifier
                == walletIdentifier
        )
        #expect(recorded.walletReservationReference.generation == 42)
    }

    @Test("Session owner starts, publishes, and resumes through Base-only types")
    func runFreshPrivateDeploymentBoundary() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 100_000,
            usage: .change,
            hashByte: 0xd2
        )
        let journalProbe = MosaicAttemptJournalProbeActor()
        let binding = try #require(Runtime.Binding(
            attemptIdentifier: Data(repeating: 0x51, count: 32),
            generationIdentifier: Data(repeating: 0x52, count: 32),
            materialIdentifier: Data(repeating: 0x53, count: 32)
        ))
        let walletIdentifier = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-0000000000d2")
        )
        let transactionReader = OpalBase.Network.TransactionReader(
            fetchRawTransaction: { _ in Data() }
        )
        let host = try await Runtime.createFreshApplicationHost(
            account: account,
            binding: binding,
            discoveryEpochStartUnixSeconds: 1_800_000_000,
            walletReservationIdentifier: walletIdentifier,
            walletGeneration: 43,
            selectedInputs: [selectedInput],
            outputAmountsSatoshis: [99_823],
            transactionReader: transactionReader,
            journalAttempt: .init(
                try await journalProbe.makeFreshAttempt()
            )
        )
        let persistence = MosaicFusionRecoveryPersistenceProbe(
            blockFirstTransition: true
        )
        let relayProbe = MosaicPrivateDeploymentRelayProbe()
        let capabilities = Runtime.PrivateDeploymentCapabilities(
            recoveryPersistence: .init { transition in
                try await persistence.persist(transition)
            },
            relays: .init(provisionRoutes: { request in
                try await relayProbe.provisionRoutes(for: request)
            })
        )
        let documents = try MosaicPrivateDeploymentDocumentFixture.make()
        let sessionOwner = try await host.makeSessionOwner()

        let beginTask = Task {
            try await sessionOwner.beginPrivateDeployment(
                opaquePoolDocument: documents.opaquePoolDocument,
                relaySetDocument: documents.relaySetDocument,
                capabilities: capabilities
            )
        }
        await persistence.waitUntilFirstTransitionIsBlocked()
        await #expect(throws: Runtime.Failure.operationInProgress) {
            _ = try await sessionOwner.resumePrivateDeployment(
                capabilities: capabilities
            )
        }
        await persistence.releaseFirstTransition()
        let progress = try await beginTask.value

        #expect(progress == .awaitingInput(.discovery))
        #expect(await persistence.transitionCount() == 2)
        #expect(await persistence.readSnapshot()?.isEmpty == false)
        #expect(await relayProbe.requestCount() == 0)

        let signing = Runtime.PrivateDeploymentSigningMaterial(
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
        let publicationProgress = try await sessionOwner
            .prepareAvailabilityBeacon(
                proofOfWorkNonce: 988_699,
                createdAtUnixSeconds: 1_800_000_001,
                signing: signing,
                capabilities: capabilities
            )

        #expect(publicationProgress == .awaitingInput(.discovery))
        #expect(await persistence.transitionCount() == 4)
        #expect(await relayProbe.requestCount() == 1)
        await #expect(
            throws: Runtime.Failure.oneTimeCapabilityAlreadyClaimed
        ) {
            _ = try await sessionOwner.prepareAvailabilityBeacon(
                proofOfWorkNonce: 988_699,
                createdAtUnixSeconds: 1_800_000_001,
                signing: signing,
                capabilities: capabilities
            )
        }

        let recoveryOwner = try await Runtime.loadApplicationRecoveryOwner(
            account: account,
            binding: binding,
            expectedWalletReservationIdentifier: walletIdentifier,
            expectedWalletGeneration: 43,
            transactionReader: transactionReader,
            fusionRecoverySnapshot: try #require(
                await persistence.readSnapshot()
            ),
            journalRecovery: .init(
                try await journalProbe.loadRecovery()
            )
        )
        let recoveredProgress = try await recoveryOwner.makeSessionOwner()
            .resumePrivateDeployment(capabilities: capabilities)

        #expect(recoveredProgress == .awaitingInput(.discovery))
        #expect(await persistence.transitionCount() == 4)
    }

    @Test("App-owned capability surface contains no raw Fusion type")
    func constructPostManifestCapabilitiesFromBaseTypes() throws {
        let binding = try #require(Runtime.Binding(
            attemptIdentifier: Data(repeating: 0x41, count: 32),
            generationIdentifier: Data(repeating: 0x42, count: 32),
            materialIdentifier: Data(repeating: 0x43, count: 32)
        ))
        let journals = Runtime.PostManifestJournalPersistence(
            load: { _, observed in
                #expect(observed == binding)
                return nil
            },
            compareAndSwap: { _, observed, _, replacement in
                #expect(observed == binding)
                return replacement
            }
        )
        let relays = Runtime.PostManifestRelayCapabilities(
            provisionRoutes: { _ in [] },
            makeSubscriptionIdentifier: { _, _ in "subscription" },
            maximumSubscriptionIdentifierByteCount: 64
        )
        let timing = Runtime.PostManifestTimingCapabilities(
            currentUnixSeconds: { 1_800_000_000 },
            makeLayerTimestamps: { request in
                .init(
                    phaseStartUnixSeconds: 1_800_000_000,
                    currentUnixSeconds: 1_800_000_001,
                    sealCreatedAt: request.expiryUnixSeconds - 2,
                    giftWrapCreatedAt: request.expiryUnixSeconds - 1
                )
            }
        )
        _ = Runtime.PostManifestRuntimeCapabilities(
            relays: relays,
            timing: timing,
            journals: journals
        )
        #expect(
            Runtime.Binding(
                attemptIdentifier: Data(repeating: 0, count: 31),
                generationIdentifier: binding.generationIdentifier,
                materialIdentifier: binding.materialIdentifier
            ) == nil
        )
    }
}

private actor MosaicFusionRecoveryPersistenceProbe {
    typealias Transition = OpalBase.Account.MosaicPrivateAlphaRuntime
        .FusionRecoveryTransition

    private let blockFirstTransition: Bool
    private var snapshot: Data?
    private var transitions: [Transition] = []
    private var didBlockFirstTransition = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(blockFirstTransition: Bool = false) {
        self.blockFirstTransition = blockFirstTransition
    }

    func persist(_ transition: Transition) async throws -> Data {
        if blockFirstTransition, !didBlockFirstTransition {
            didBlockFirstTransition = true
            let waiters = blockedWaiters
            blockedWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }
        guard transition.expectedSnapshot == snapshot else {
            throw OpalBase.Account.MosaicPrivateAlphaRuntime.Failure
                .invalidRecoveryState
        }
        snapshot = transition.replacementSnapshot
        transitions.append(transition)
        return transition.replacementSnapshot
    }

    func transitionCount() -> Int { transitions.count }

    func readSnapshot() -> Data? { snapshot }

    func waitUntilFirstTransitionIsBlocked() async {
        guard blockFirstTransition, !didBlockFirstTransition else { return }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func releaseFirstTransition() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor MosaicPrivateDeploymentRelayProbe {
    typealias Runtime = OpalBase.Account.MosaicPrivateAlphaRuntime

    private var requests: [Runtime.PrivateDeploymentRouteRequest] = []

    func provisionRoutes(
        for request: Runtime.PrivateDeploymentRouteRequest
    ) throws -> [Runtime.PostManifestProvisionedRoute] {
        requests.append(request)
        let identifiers = [
            "00000000-0000-0000-0000-000000000101",
            "00000000-0000-0000-0000-000000000102",
            "00000000-0000-0000-0000-000000000103",
        ]
        return try zip(
            request.relayEndpointIdentifiers,
            identifiers
        ).map { endpoint, identifier in
            Runtime.PostManifestProvisionedRoute(
                relayEndpointIdentifier: endpoint,
                connection: MosaicAcknowledgingTorConnection(),
                isolationIdentifier: try #require(
                    UUID(uuidString: identifier)
                )
            )
        }
    }

    func requestCount() -> Int { requests.count }
}

private actor MosaicAcknowledgingTorConnection:
    OpalBase.Account.MosaicPrivateAlphaRuntime.TorWebSocketConnection {
    typealias Runtime = OpalBase.Account.MosaicPrivateAlphaRuntime
    typealias MessageStream = Runtime.TorWebSocketConnection.MessageStream

    private var continuation: MessageStream.Continuation?

    func open(
        maximumIncomingMessageByteCount _: Int
    ) async throws -> MessageStream {
        guard continuation == nil else {
            throw Runtime.Failure.operationInProgress
        }
        let stream = MessageStream.makeStream()
        continuation = stream.continuation
        return stream.stream
    }

    func send(text: String) async throws {
        guard let continuation,
              let message = try JSONSerialization.jsonObject(
                  with: Data(text.utf8)
              ) as? [Any],
              message.count == 2,
              message[0] as? String == "EVENT",
              let event = message[1] as? [String: Any],
              let identifier = event["id"] as? String else {
            throw Runtime.Failure.invalidRecoveryState
        }
        let acknowledgement = try JSONSerialization.data(
            withJSONObject: ["OK", identifier, true, ""]
        )
        continuation.yield(.text(acknowledgement))
    }

    func close() async {
        continuation?.finish()
        continuation = nil
    }
}
#endif
