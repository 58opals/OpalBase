// OpalBase+Account+MosaicPrivateAlphaRuntime+Transport.swift

#if os(macOS)
import Foundation
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Exact text or binary payload received from a Tor-only WebSocket route.
    @_spi(MosaicPrivateAlpha)
    public enum TorWebSocketMessage: Sendable, Equatable {
        case text(Data)
        case binary(Data)
    }

    /// App-owned WebSocket capability already constrained to one Tor-only route.
    ///
    /// `close()` must be idempotent, finish the message stream, unblock pending
    /// `open` and `send` work, and return only after that connection is closed.
    @_spi(MosaicPrivateAlpha)
    public protocol TorWebSocketConnection: Actor {
        typealias MessageStream = AsyncThrowingStream<
            TorWebSocketMessage,
            Swift.Error
        >

        func open(
            maximumIncomingMessageByteCount: Int
        ) async throws -> MessageStream
        func send(text: String) async throws
        func close() async
    }

    /// Package-owned request for one exact set of endpoint-bound Tor routes.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapRouteRequest: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha)
        public struct Binding: Hashable, Sendable {
            @_spi(MosaicPrivateAlpha) public let attemptIdentifier: Data
            @_spi(MosaicPrivateAlpha) public let generationIdentifier: Data
            @_spi(MosaicPrivateAlpha) public let materialIdentifier: Data
        }

        @_spi(MosaicPrivateAlpha)
        public enum Purpose: Sendable, Equatable {
            case inbound
            case outbound
        }

        @_spi(MosaicPrivateAlpha) public let binding: Binding
        @_spi(MosaicPrivateAlpha) public let purpose: Purpose
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let relayEndpointIdentifiers: [String]

        init(
            _ request: OpalFusion.MosaicPrivateAlphaRuntime
                .TransportBootstrapRouteRequest
        ) {
            binding = .init(
                attemptIdentifier: request.binding.attemptIdentifier,
                generationIdentifier: request.binding.generationIdentifier,
                materialIdentifier: request.binding.materialIdentifier
            )
            purpose = request.purpose == .inbound ? .inbound : .outbound
            recipientEventIdentity = request.recipientEventIdentity
            relayEndpointIdentifiers = request.relayEndpointIdentifiers
        }
    }

    /// One endpoint-bound Tor connection with app-attested isolation identity.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestProvisionedRoute: Sendable {
        @_spi(MosaicPrivateAlpha) public let relayEndpointIdentifier: String
        @_spi(MosaicPrivateAlpha) public let connection:
            any TorWebSocketConnection
        @_spi(MosaicPrivateAlpha) public let isolationIdentifier: UUID

        @_spi(MosaicPrivateAlpha)
        public init(
            relayEndpointIdentifier: String,
            connection: any TorWebSocketConnection,
            isolationIdentifier: UUID
        ) {
            self.relayEndpointIdentifier = relayEndpointIdentifier
            self.connection = connection
            self.isolationIdentifier = isolationIdentifier
        }

        func fusionRoute() -> OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestProvisionedRoute {
            .init(
                relayEndpointIdentifier: relayEndpointIdentifier,
                connection: MosaicPrivateAlphaTorWebSocketConnectionAdapter(
                    connection
                ),
                isolationIdentifier: isolationIdentifier
            )
        }
    }

    /// One exact regular gift wrap prepared for durable three-relay publication.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapPublication: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let canonicalEventBytes: Data
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data
        @_spi(MosaicPrivateAlpha) public let senderEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let wrapperEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let messageIdentifier: Data
        @_spi(MosaicPrivateAlpha) public let operationIdentifier: Data

        let storage: MosaicPrivateAlphaTransportBootstrapPublicationStorage

        init(
            _ publication: OpalFusion.MosaicPrivateAlphaRuntime
                .TransportBootstrapPublication
        ) {
            canonicalEventBytes = publication.canonicalEventBytes
            canonicalDocument = publication.canonicalDocument
            senderEventIdentity = publication.senderEventIdentity
            recipientEventIdentity = publication.recipientEventIdentity
            wrapperEventIdentity = publication.wrapperEventIdentity
            messageIdentifier = publication.messageIdentifier
            operationIdentifier = publication.operationIdentifier
            storage = .init(publication)
        }

        public static func == (
            lhs: Self,
            rhs: Self
        ) -> Bool {
            lhs.canonicalEventBytes == rhs.canonicalEventBytes
                && lhs.canonicalDocument == rhs.canonicalDocument
                && lhs.senderEventIdentity == rhs.senderEventIdentity
                && lhs.recipientEventIdentity == rhs.recipientEventIdentity
                && lhs.wrapperEventIdentity == rhs.wrapperEventIdentity
                && lhs.messageIdentifier == rhs.messageIdentifier
                && lhs.operationIdentifier == rhs.operationIdentifier
        }

        var fusionPublication: OpalFusion.MosaicPrivateAlphaRuntime
            .TransportBootstrapPublication {
            storage.publication
        }
    }

    /// Durable replay and wrapper-freshness evidence for reconnect recovery.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapReplayEntry: Sendable, Hashable {
        @_spi(MosaicPrivateAlpha) public let wrapperEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let messageIdentifier: Data

        @_spi(MosaicPrivateAlpha)
        public init(
            wrapperEventIdentity: Data,
            messageIdentifier: Data
        ) {
            self.wrapperEventIdentity = wrapperEventIdentity
            self.messageIdentifier = messageIdentifier
        }

        init(
            _ entry: OpalFusion.MosaicPrivateAlphaRuntime
                .TransportBootstrapReplayEntry
        ) {
            self.init(
                wrapperEventIdentity: entry.wrapperEventIdentity,
                messageIdentifier: entry.messageIdentifier
            )
        }

        var fusionEntry: OpalFusion.MosaicPrivateAlphaRuntime
            .TransportBootstrapReplayEntry {
            .init(
                wrapperEventIdentity: wrapperEventIdentity,
                messageIdentifier: messageIdentifier
            )
        }
    }

    /// App-owned Tor route construction accepted by the protocol runtime.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapRelayCapabilities: Sendable {
        let provisionRoutes: @Sendable (TransportBootstrapRouteRequest)
            async throws -> [PostManifestProvisionedRoute]
        let makeSubscriptionIdentifier: @Sendable (
            TransportBootstrapRouteRequest,
            String
        ) throws -> String
        let maximumPendingEventCount: Int
        let maximumPendingRelayOutputCount: Int

        @_spi(MosaicPrivateAlpha)
        public init(
            provisionRoutes: @escaping @Sendable (
                TransportBootstrapRouteRequest
            ) async throws -> [PostManifestProvisionedRoute],
            makeSubscriptionIdentifier: @escaping @Sendable (
                TransportBootstrapRouteRequest,
                String
            ) throws -> String,
            maximumPendingEventCount: Int = 256,
            maximumPendingRelayOutputCount: Int = 64
        ) {
            self.provisionRoutes = provisionRoutes
            self.makeSubscriptionIdentifier = makeSubscriptionIdentifier
            self.maximumPendingEventCount = maximumPendingEventCount
            self.maximumPendingRelayOutputCount =
                maximumPendingRelayOutputCount
        }

        func fusionCapabilities() -> OpalFusion.MosaicPrivateAlphaRuntime
            .TransportBootstrapRelayCapabilities {
            let provisionRoutes = provisionRoutes
            let makeSubscriptionIdentifier = makeSubscriptionIdentifier
            return .init(
                provisionRoutes: { fusionRequest in
                    let request = TransportBootstrapRouteRequest(
                        fusionRequest
                    )
                    let routes = try await provisionRoutes(request)
                    guard Set(routes.map {
                        ObjectIdentifier($0.connection as AnyObject)
                    }).count == routes.count else {
                        for route in routes {
                            await route.connection.close()
                        }
                        throw OpalFusion.MosaicPrivateAlphaRuntime
                            .TransportBootstrapFailure
                            .invalidRelayAllocation
                    }
                    return routes.map { $0.fusionRoute() }
                },
                makeSubscriptionIdentifier: {
                    fusionRequest,
                    endpointIdentifier in
                    try makeSubscriptionIdentifier(
                        TransportBootstrapRouteRequest(fusionRequest),
                        endpointIdentifier
                    )
                },
                maximumPendingEventCount: maximumPendingEventCount,
                maximumPendingRelayOutputCount:
                    maximumPendingRelayOutputCount
            )
        }
    }

    /// Relay delivery capabilities bound to durable acceptance recording.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapPublicationCapabilities: Sendable {
        let relays: TransportBootstrapRelayCapabilities
        let loadAcceptedRelayEndpointIdentifiers: @Sendable (Data)
            async throws -> [String]
        let recordAcceptedRelayEndpointIdentifier: @Sendable (
            Data,
            String
        ) async throws -> Void

        @_spi(MosaicPrivateAlpha)
        public init(
            relays: TransportBootstrapRelayCapabilities,
            loadAcceptedRelayEndpointIdentifiers: @escaping @Sendable (
                Data
            ) async throws -> [String],
            recordAcceptedRelayEndpointIdentifier: @escaping @Sendable (
                Data,
                String
            ) async throws -> Void
        ) {
            self.relays = relays
            self.loadAcceptedRelayEndpointIdentifiers =
                loadAcceptedRelayEndpointIdentifiers
            self.recordAcceptedRelayEndpointIdentifier =
                recordAcceptedRelayEndpointIdentifier
        }

        func fusionCapabilities() -> OpalFusion.MosaicPrivateAlphaRuntime
            .TransportBootstrapPublicationCapabilities {
            .init(
                relays: relays.fusionCapabilities(),
                loadAcceptedRelayEndpointIdentifiers:
                    loadAcceptedRelayEndpointIdentifiers,
                recordAcceptedRelayEndpointIdentifier:
                    recordAcceptedRelayEndpointIdentifier
            )
        }
    }
}

final class MosaicPrivateAlphaTransportBootstrapPublicationStorage: Sendable {
    let publication: OpalFusion.MosaicPrivateAlphaRuntime
        .TransportBootstrapPublication

    init(
        _ publication: OpalFusion.MosaicPrivateAlphaRuntime
            .TransportBootstrapPublication
    ) {
        self.publication = publication
    }
}

actor MosaicPrivateAlphaTorWebSocketConnectionAdapter:
    OpalFusion.MosaicPrivateAlphaRuntime.TorWebSocketConnection
{
    typealias BaseRuntime = OpalBase.Account.MosaicPrivateAlphaRuntime
    typealias FusionRuntime = OpalFusion.MosaicPrivateAlphaRuntime
    typealias MessageStream = AsyncThrowingStream<
        FusionRuntime.TorWebSocketMessage,
        Swift.Error
    >

    private let connection: any BaseRuntime.TorWebSocketConnection

    init(_ connection: any BaseRuntime.TorWebSocketConnection) {
        self.connection = connection
    }

    func open(
        maximumIncomingMessageByteCount: Int
    ) async throws -> MessageStream {
        let source = try await connection.open(
            maximumIncomingMessageByteCount:
                maximumIncomingMessageByteCount
        )
        let (stream, continuation) = MessageStream.makeStream(
            bufferingPolicy: .bufferingOldest(1)
        )
        let connection = connection
        let forwardingTask = Task {
            do {
                for try await message in source {
                    let result: MessageStream.Continuation.YieldResult
                    switch message {
                    case let .text(bytes):
                        result = continuation.yield(.text(bytes))
                    case let .binary(bytes):
                        result = continuation.yield(.binary(bytes))
                    }
                    switch result {
                    case .enqueued:
                        break
                    case .dropped:
                        await connection.close()
                        continuation.finish(
                            throwing: Failure.boundedBufferExceeded
                        )
                        return
                    case .terminated:
                        return
                    @unknown default:
                        await connection.close()
                        continuation.finish(
                            throwing: Failure.boundedBufferExceeded
                        )
                        return
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in
            forwardingTask.cancel()
            Task { await connection.close() }
        }
        return stream
    }

    func send(text: String) async throws {
        try await connection.send(text: text)
    }

    func close() async {
        await connection.close()
    }

    private enum Failure: Error, Sendable {
        case boundedBufferExceeded
    }
}
#endif
