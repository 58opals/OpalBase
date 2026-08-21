// AccountMosaicPrivateAlphaPostManifestBridgeValidator.swift

#if os(macOS)
import Foundation
import OpalCrypto
@_spi(MosaicPrivateAlpha) @testable import OpalFusion
import Synchronization
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalBase

@Suite("OpalBase.Account Mosaic post-manifest bridge", .tags(.unit, .wallet))
struct AccountMosaicPrivateAlphaPostManifestBridgeValidator {
    typealias BaseRuntime = OpalBase.Account.MosaicPrivateAlphaRuntime
    typealias FusionRuntime = OpalFusion.MosaicPrivateAlphaRuntime

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
                    return .init(
                        phaseStartUnixSeconds: 1_800_000_000,
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
            expiryUnixSeconds: 1_800_000_010
        ))
        #expect(timestamps.currentUnixSeconds == 1_800_000_001)
        #expect(timestamps.giftWrapCreatedAt == 1_800_000_009)
    }
}
#endif
