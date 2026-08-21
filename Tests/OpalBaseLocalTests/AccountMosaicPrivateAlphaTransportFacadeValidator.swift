// AccountMosaicPrivateAlphaTransportFacadeValidator.swift

#if os(macOS)
import Foundation
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalBase

@Suite("OpalBase.Account Mosaic private-alpha transport facade")
struct AccountMosaicPrivateAlphaTransportFacadeValidator {
    typealias Runtime = OpalBase.Account.MosaicPrivateAlphaRuntime

    @Test("Transport contracts are consumable through OpalBase alone")
    func exposeTransportContractsThroughOpalBase() async throws {
        let connection = MosaicPrivateAlphaTransportFacadeConnectionProbe()
        let route = Runtime.PostManifestProvisionedRoute(
            relayEndpointIdentifier: "relay-1",
            connection: connection,
            isolationIdentifier: UUID()
        )
        let relayCapabilities = Runtime.TransportBootstrapRelayCapabilities(
            provisionRoutes: { _ in [route] },
            makeSubscriptionIdentifier: { _, endpointIdentifier in
                "mosaic-\(endpointIdentifier)"
            }
        )
        let publicationCapabilities = Runtime
            .TransportBootstrapPublicationCapabilities(
                relays: relayCapabilities,
                loadAcceptedRelayEndpointIdentifiers: { _ in [] },
                recordAcceptedRelayEndpointIdentifier: { _, _ in }
            )
        let replayEntry = Runtime.TransportBootstrapReplayEntry(
            wrapperEventIdentity: Data(repeating: 0x11, count: 32),
            messageIdentifier: Data(repeating: 0x22, count: 32)
        )
        let message = Runtime.TorWebSocketMessage.text(Data([0x33]))

        _ = publicationCapabilities
        _ = Runtime.TransportBootstrapRouteRequest.self
        _ = Runtime.TransportBootstrapPublication.self
        #expect(route.relayEndpointIdentifier == "relay-1")
        #expect(replayEntry.wrapperEventIdentity.count == 32)
        #expect(message == .text(Data([0x33])))
    }
}

private actor MosaicPrivateAlphaTransportFacadeConnectionProbe:
    OpalBase.Account.MosaicPrivateAlphaRuntime.TorWebSocketConnection
{
    typealias Runtime = OpalBase.Account.MosaicPrivateAlphaRuntime
    typealias MessageStream = AsyncThrowingStream<
        Runtime.TorWebSocketMessage,
        Swift.Error
    >

    func open(
        maximumIncomingMessageByteCount: Int
    ) async throws -> MessageStream {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func send(text: String) async throws {}

    func close() async {}
}
#endif
