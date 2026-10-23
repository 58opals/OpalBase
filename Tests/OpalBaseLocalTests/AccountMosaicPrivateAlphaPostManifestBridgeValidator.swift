// AccountMosaicPrivateAlphaPostManifestBridgeValidator.swift

#if os(macOS)
import Foundation
import OpalCrypto
@_spi(MosaicPrivateAlpha) import OpalFusion
@_spi(MosaicPrivateAlpha) @testable import MosaicEngine
import Synchronization
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalBase
@testable import OpalBaseCore

@Suite("OpalBase.Account Mosaic post-manifest bridge", .tags(.unit, .wallet))
struct AccountMosaicPrivateAlphaPostManifestBridgeValidator {
    typealias BaseRuntime = OpalBase.Account.MosaicPrivateAlphaRuntime
    typealias FusionRuntime = OpalFusion.MosaicPrivateAlphaRuntime

    @Test("Post-manifest relay bridge preserves connection identity across groups", arguments: [false, true])
    func preserveConnectionIdentityAcrossGroups(reusesConnection: Bool) async throws {
        let binding = try FusionRuntime.Binding(
            attemptIdentifier: Data(repeating: 0x51, count: 32),
            generationIdentifier: Data(repeating: 0x52, count: 32),
            materialIdentifier: Data(repeating: 0x53, count: 32)
        )
        let endpoints = (1 ... 3).map { "wss://relay-\($0).example/" }
        let firstConnections = (0 ..< 3).map { _ in MosaicPostManifestConnectionProbe() }
        let secondConnections = (0 ..< 3).map { index in
            reusesConnection && index == 0 ? firstConnections[0] : MosaicPostManifestConnectionProbe()
        }
        let connections = firstConnections + secondConnections
        let recipients = [Data(repeating: 0x61, count: 32), Data(repeating: 0x62, count: 32)]
        let groups = [firstConnections, secondConnections].enumerated().map { groupIndex, groupConnections in
            BaseRuntime.PostManifestProvisionedRouteGroup(
                recipientEventIdentity: recipients[groupIndex],
                routes: groupConnections.enumerated().map { routeIndex, connection in
                    .init(relayEndpointIdentifier: endpoints[routeIndex], connection: connection,
                          isolationIdentifier: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                                          UInt8(groupIndex * 3 + routeIndex + 1))))
                }
            )
        }
        let capabilities = BaseRuntime.PostManifestRelayCapabilities(
            provisionRoutes: { _ in groups },
            makeSubscriptionIdentifier: { _, endpoint in endpoint },
            maximumSubscriptionIdentifierByteCount: 64
        )
        let requests = recipients.map {
            FusionRuntime.PostManifestRouteRequest(binding: binding, purpose: .outboundControl,
                recipientEventIdentity: $0, relayEndpointIdentifiers: endpoints)
        }
        if reusesConnection {
            await #expect(throws: FusionRuntime.Failure.invalidStateTransition) {
                _ = try await capabilities.fusionCapabilities().provisionRoutes(requests)
            }
        } else {
            let projected = try await capabilities.fusionCapabilities().provisionRoutes(requests)
            #expect(projected.map(\.recipientEventIdentity) == recipients)
            #expect(projected.map { $0.routes.map(\.relayEndpointIdentifier) } == [endpoints, endpoints])
        }
        var closesBeforeCleanup: [Int] = []
        var opensBeforeCleanup: [Int] = []
        for connection in connections {
            closesBeforeCleanup.append(await connection.closeCount)
            opensBeforeCleanup.append(await connection.openCount)
        }
        for connection in connections { await connection.close() }
        #expect(opensBeforeCleanup.allSatisfy { $0 == 0 })
        #expect(closesBeforeCleanup.allSatisfy { $0 == (reusesConnection ? 1 : 0) })
    }

    @Test("Base preserves opaque contributor authorization recovery bytes")
    func preserveAuthorizationRecoveryBytes() {
        let component = Data([0x01]) + Data(repeating: 0x71, count: 400)
        let bchSignature = Data([0x01]) + Data(repeating: 0x72, count: 400)
        let baseState = BaseRuntime
            .PostManifestComponentSlotAuthorizationRecoveryState(
                componentRequest: component,
                bchSignatureRequest: bchSignature
            )

        let fusionState = baseState.fusionRecoveryState
        #expect(fusionState.componentRequest == component)
        #expect(fusionState.bchSignatureRequest == bchSignature)
        #expect(
            BaseRuntime.PostManifestComponentSlotAuthorizationRecoveryState(
                fusionState
            ) == baseState
        )
    }

    @Test("Base-owned runtime capabilities preserve exact Fusion requests")
    func preserveExactCapabilityRequests() async throws {
        let binding = try FusionRuntime.Binding(
            attemptIdentifier: Data(repeating: 0x51, count: 32),
            generationIdentifier: Data(repeating: 0x52, count: 32),
            materialIdentifier: Data(repeating: 0x53, count: 32)
        )
        let baseBinding = BaseRuntime.Binding(binding)
        let observedJournals = Mutex<[BaseRuntime.PostManifestJournal]>([])
        let observedRoutes = Mutex<[BaseRuntime.PostManifestRouteRequest]>([])
        let observedPublications = Mutex<[
            BaseRuntime.PostManifestAnonymousPublicationRequest
        ]>([])
        let baseCapabilities = BaseRuntime.PostManifestRuntimeCapabilities(
            relays: .init(
                provisionRoutes: { requests in
                    observedRoutes.withLock { $0.append(contentsOf: requests) }
                    return []
                },
                makeSubscriptionIdentifier: { request, endpoint in
                    #expect(request.binding == baseBinding)
                    return endpoint + "-subscription"
                },
                awaitAnonymousPublicationPermit: { request in
                    observedPublications.withLock { $0.append(request) }
                },
                maximumSubscriptionIdentifierByteCount: 64
            ),
            timing: .init(
                currentUnixSeconds: { 1_800_000_000 },
                makeLayerTimestamps: { request in
                    #expect(request.phase == .walletReservation)
                    #expect(
                        request.phaseStartUnixSeconds == 1_800_000_000
                    )
                    return .init(
                        phaseStartUnixSeconds:
                            request.phaseStartUnixSeconds,
                        currentUnixSeconds: 1_800_000_001,
                        sealCreatedAt: request.expiryUnixSeconds - 2,
                        giftWrapCreatedAt: request.expiryUnixSeconds - 1
                    )
                }
            ),
            journals: .init(
                load: { journal, observedBinding in
                    #expect(observedBinding == baseBinding)
                    observedJournals.withLock { $0.append(journal) }
                    return nil
                },
                compareAndSwap: {
                    journal,
                    observedBinding,
                    expected,
                    replacement in
                    #expect(observedBinding == baseBinding)
                    #expect(expected == nil)
                    observedJournals.withLock { $0.append(journal) }
                    return replacement
                }
            )
        )
        let recipientKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: Data(repeating: 0, count: 31) + Data([1])
        )
        let mailboxes = FusionRuntime.PostManifestMailboxCapabilities(
            controlMailboxes: [],
            localControlRecipientSigningKey: recipientKey,
            anonymous: .contributor([])
        )
        let capabilities = baseCapabilities.fusionCapabilities(
            mailboxes: mailboxes
        )
        let replacement = Data([0x61])

        #expect(try capabilities.admissionPersistence.load(binding) == nil)
        #expect(
            try capabilities.admissionPersistence.compareAndSwap(
                binding,
                nil,
                replacement
            ) == replacement
        )
        #expect(try capabilities.publicationPersistence.load(binding) == nil)
        #expect(try capabilities.terminalPersistence.load(binding) == nil)
        #expect(
            observedJournals.withLock { $0 }
                == [.admission, .admission, .publication, .terminal]
        )

        let routeRequest = FusionRuntime.PostManifestRouteRequest(
            binding: binding,
            purpose: .outboundAnonymousBCHSignatures,
            recipientEventIdentity: Data(repeating: 0x62, count: 32),
            relayEndpointIdentifiers: ["wss://relay.example"]
        )
        #expect(try await capabilities.relays.provisionRoutes([routeRequest]).isEmpty)
        #expect(observedRoutes.withLock { $0 }.count == 1)
        #expect(
            observedRoutes.withLock { $0.first?.purpose }
                == .outboundAnonymousBCHSignatures
        )
        #expect(
            try capabilities.relays.makeSubscriptionIdentifier(
                routeRequest,
                "relay"
            ) == "relay-subscription"
        )
        try await capabilities.relays.awaitAnonymousPublicationPermit(
            .init(
                kind: .localBCHSignatures,
                recipientEventIdentity: Data(repeating: 0x63, count: 32)
            )
        )
        #expect(
            observedPublications.withLock { $0.first?.kind }
                == .localBCHSignatures
        )

        let timestamps = try capabilities.timing.makeLayerTimestamps(.init(
            recipientEventIdentity: nil,
            phase: .walletReservation,
            sequence: 1,
            phaseStartUnixSeconds: 1_800_000_000,
            expiryUnixSeconds: 1_800_000_010
        ))
        #expect(timestamps.currentUnixSeconds == 1_800_000_001)
        #expect(timestamps.giftWrapCreatedAt == 1_800_000_009)
    }
}

private actor MosaicPostManifestConnectionProbe: OpalBase.Account.MosaicPrivateAlphaRuntime.TorWebSocketConnection {
    typealias MessageStream = OpalBase.Account.MosaicPrivateAlphaRuntime.TorWebSocketConnection.MessageStream
    private(set) var openCount = 0
    private(set) var closeCount = 0

    func open(maximumIncomingMessageByteCount: Int) async throws -> MessageStream {
        openCount += 1
        return MessageStream { $0.finish() }
    }

    func send(text: String) async throws {}

    func close() async {
        guard closeCount == 0 else { return }
        closeCount = 1
    }
}
#endif
