// AccountMosaicPrivateAlphaTransportBridgeValidator.swift

#if os(macOS)
import Foundation
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalBase
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

@Suite("OpalBase.Account Mosaic private-alpha transport bridge")
struct AccountMosaicPrivateAlphaTransportBridgeValidator {
    typealias BaseRuntime = OpalBase.Account.MosaicPrivateAlphaRuntime
    typealias FusionRuntime = OpalFusion.MosaicPrivateAlphaRuntime

    @Test("WebSocket bridge retains a bounded burst while its consumer starts")
    func webSocketAdapterPreservesBurst() async throws {
        let expected = (0 ..< 16).map { Data([UInt8($0)]) }
        let connection = MosaicPrivateAlphaTransportBridgeConnectionProbe(messages: expected.map { .text($0) })
        let adapter = MosaicPrivateAlphaTorWebSocketConnectionAdapter(connection)
        let stream = try await adapter.open(maximumIncomingMessageByteCount: 512)
        // Consumer scheduling may lag the source. The bridge must not insert
        // a smaller queue than the source's already bounded receive buffer.
        try await Task.sleep(for: .milliseconds(50))
        var received: [Data] = []
        for try await event in stream {
            guard case let .text(bytes) = event else { Issue.record("Unexpected message kind"); continue }
            received.append(bytes)
        }
        #expect(received == expected)
        await adapter.close()
    }

    @Test("Canceling a blocked bridge read closes the app-owned connection")
    func cancellationClosesPullRead() async throws {
        let connection = MosaicPrivateAlphaTransportBridgeConnectionProbe(messages: [], holdsOpen: true)
        let adapter = MosaicPrivateAlphaTorWebSocketConnectionAdapter(connection)
        let stream = try await adapter.open(maximumIncomingMessageByteCount: 512)
        let reader = Task {
            var iterator = stream.makeAsyncIterator()
            _ = try await iterator.next()
        }
        try await Task.sleep(for: .milliseconds(10))
        reader.cancel()
        await #expect(throws: CancellationError.self) { try await reader.value }
        #expect(await connection.snapshot().closeCount >= 1)
    }

    @Test("WebSocket adapter maps messages and lifecycle operations exactly")
    func webSocketAdapterMapsMessagesAndLifecycle() async throws {
        let expectedBytes = Data([0x11, 0x22])
        let connection = MosaicPrivateAlphaTransportBridgeConnectionProbe(
            message: .binary(expectedBytes)
        )
        let adapter = MosaicPrivateAlphaTorWebSocketConnectionAdapter(
            connection
        )

        let stream = try await adapter.open(
            maximumIncomingMessageByteCount: 512
        )
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == .binary(expectedBytes))
        #expect(try await iterator.next() == nil)

        try await adapter.send(text: "hello")
        await adapter.close()
        let snapshot = await connection.snapshot()
        #expect(snapshot.maximumIncomingMessageByteCount == 512)
        #expect(snapshot.sentTexts == ["hello"])
        #expect(snapshot.closeCount >= 1)
    }

    @Test("Relay bridge preserves duplicate connection rejection")
    func relayBridgePreservesDuplicateConnectionRejection() async throws {
        let connection = MosaicPrivateAlphaTransportBridgeConnectionProbe()
        let endpointIdentifiers = ["relay-1", "relay-2"]
        let capabilities = BaseRuntime.TransportBootstrapRelayCapabilities(
            provisionRoutes: { request in
                #expect(
                    request.binding.attemptIdentifier
                        == Data(repeating: 0x21, count: 32)
                )
                #expect(request.purpose == .outbound)
                #expect(
                    request.relayEndpointIdentifiers == endpointIdentifiers
                )
                return endpointIdentifiers.enumerated().map { index, endpoint in
                    BaseRuntime.PostManifestProvisionedRoute(
                        relayEndpointIdentifier: endpoint,
                        connection: connection,
                        isolationIdentifier: UUID(
                            uuid: (
                                0, 0, 0, 0,
                                0, 0, 0, 0,
                                0, 0, 0, 0,
                                0, 0, 0, UInt8(index + 1)
                            )
                        )
                    )
                }
            },
            makeSubscriptionIdentifier: { _, endpointIdentifier in
                "mosaic-\(endpointIdentifier)"
            }
        )
        let request = FusionRuntime.TransportBootstrapRouteRequest(
            binding: try fusionBinding(),
            purpose: .outbound,
            recipientEventIdentity: Data(repeating: 0x24, count: 32),
            relayEndpointIdentifiers: endpointIdentifiers
        )

        await #expect(
            throws: FusionRuntime.TransportBootstrapFailure
                .invalidRelayAllocation
        ) {
            try await capabilities.fusionCapabilities()
                .provisionValidatedRoutes(for: request)
        }
        #expect(await connection.snapshot().closeCount == 2)
    }

    @Test("Publication bridge retains exact Fusion value behind Base fields")
    func publicationBridgeRetainsExactFusionValue() throws {
        let publication = FusionRuntime.TransportBootstrapPublication(
            canonicalEventBytes: Data("event".utf8),
            canonicalDocument: Data("document".utf8),
            senderEventIdentity: Data(repeating: 0x31, count: 32),
            recipientEventIdentity: Data(repeating: 0x32, count: 32),
            wrapperEventIdentity: Data(repeating: 0x33, count: 32),
            messageIdentifier: Data(repeating: 0x34, count: 32),
            operationIdentifier: Data(repeating: 0x35, count: 32),
            binding: try fusionBinding(),
            relayEndpointIdentifiers: ["relay-1", "relay-2", "relay-3"]
        )

        let bridged = BaseRuntime.TransportBootstrapPublication(publication)

        #expect(bridged.canonicalEventBytes == publication.canonicalEventBytes)
        #expect(bridged.canonicalDocument == publication.canonicalDocument)
        #expect(bridged.senderEventIdentity == publication.senderEventIdentity)
        #expect(
            bridged.recipientEventIdentity
                == publication.recipientEventIdentity
        )
        #expect(
            bridged.wrapperEventIdentity == publication.wrapperEventIdentity
        )
        #expect(bridged.messageIdentifier == publication.messageIdentifier)
        #expect(bridged.operationIdentifier == publication.operationIdentifier)
        #expect(bridged.fusionPublication == publication)
    }

    private func fusionBinding() throws -> FusionRuntime.Binding {
        try .init(
            attemptIdentifier: Data(repeating: 0x21, count: 32),
            generationIdentifier: Data(repeating: 0x22, count: 32),
            materialIdentifier: Data(repeating: 0x23, count: 32)
        )
    }
}

private actor MosaicPrivateAlphaTransportBridgeConnectionProbe:
    OpalBase.Account.MosaicPrivateAlphaRuntime.TorWebSocketConnection
{
    typealias Runtime = OpalBase.Account.MosaicPrivateAlphaRuntime
    typealias MessageStream = AsyncThrowingStream<
        Runtime.TorWebSocketMessage,
        Swift.Error
    >

    struct Snapshot: Sendable, Equatable {
        let maximumIncomingMessageByteCount: Int?
        let sentTexts: [String]
        let closeCount: Int
    }

    private let messages: [Runtime.TorWebSocketMessage]
    private let holdsOpen: Bool
    private var continuation: MessageStream.Continuation?
    private var maximumIncomingMessageByteCount: Int?
    private var sentTexts: [String] = []
    private var closeCount = 0

    init(message: Runtime.TorWebSocketMessage? = nil) {
        messages = message.map { [$0] } ?? []
        holdsOpen = false
    }

    init(messages: [Runtime.TorWebSocketMessage], holdsOpen: Bool = false) {
        self.messages = messages
        self.holdsOpen = holdsOpen
    }

    func open(
        maximumIncomingMessageByteCount: Int
    ) async throws -> MessageStream {
        self.maximumIncomingMessageByteCount =
            maximumIncomingMessageByteCount
        let messages = messages
        let pair = MessageStream.makeStream(bufferingPolicy: .bufferingOldest(32))
        continuation = pair.continuation
        for message in messages { pair.continuation.yield(message) }
        if !holdsOpen { pair.continuation.finish() }
        return pair.stream
    }

    func send(text: String) async throws {
        sentTexts.append(text)
    }

    func close() async {
        closeCount += 1
        continuation?.finish()
    }

    func snapshot() -> Snapshot {
        .init(
            maximumIncomingMessageByteCount:
                maximumIncomingMessageByteCount,
            sentTexts: sentTexts,
            closeCount: closeCount
        )
    }
}
#endif
