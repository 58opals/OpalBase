// OpalBase+Account+MosaicPrivateAlphaRuntime+TransportBootstrapLifecycle.swift

#if os(macOS)
import Foundation
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Authenticated document plus the exact NIP-59 replay identity that carried it.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapOpenedDocument<Document: Sendable>:
        Sendable
    {
        @_spi(MosaicPrivateAlpha) public let document: Document
        @_spi(MosaicPrivateAlpha) public let senderEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let wrapperEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let messageIdentifier: Data

        init(
            document: Document,
            senderEventIdentity: Data,
            recipientEventIdentity: Data,
            wrapperEventIdentity: Data,
            messageIdentifier: Data
        ) {
            self.document = document
            self.senderEventIdentity = senderEventIdentity
            self.recipientEventIdentity = recipientEventIdentity
            self.wrapperEventIdentity = wrapperEventIdentity
            self.messageIdentifier = messageIdentifier
        }

        init<FusionDocument>(
            _ opened: FusionRuntime
                .TransportBootstrapOpenedPublication<FusionDocument>,
            projectDocument: (FusionDocument) -> Document
        ) where FusionDocument: Sendable {
            self.init(
                document: projectDocument(opened.document),
                senderEventIdentity: opened.senderEventIdentity,
                recipientEventIdentity: opened.recipientEventIdentity,
                wrapperEventIdentity: opened.wrapperEventIdentity,
                messageIdentifier: opened.messageIdentifier
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapPublicationReceipt: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let operationIdentifier: Data
        @_spi(MosaicPrivateAlpha) public let acceptedRelayEndpointIdentifiers:
            [String]

        init(
            _ receipt: OpalFusion.MosaicPrivateAlphaRuntime
                .TransportBootstrapPublicationReceipt
        ) {
            operationIdentifier = receipt.operationIdentifier
            acceptedRelayEndpointIdentifiers =
                receipt.acceptedRelayEndpointIdentifiers
        }
    }

    /// One replay-preflighted relay event; persist its replay entry before opening it.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapInboundEvent: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let canonicalEventBytes: Data
        @_spi(MosaicPrivateAlpha) public let replayEntry:
            TransportBootstrapReplayEntry

        init(
            _ event: OpalFusion.MosaicPrivateAlphaRuntime
                .TransportBootstrapInboundEvent
        ) {
            canonicalEventBytes = event.canonicalEventBytes
            replayEntry = .init(event.replayEntry)
        }
    }

    /// Base-owned, zero-copy projection of the package-authenticated inbox stream.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapEventStream: AsyncSequence, Sendable {
        @_spi(MosaicPrivateAlpha)
        public typealias Element = TransportBootstrapInboundEvent

        @_spi(MosaicPrivateAlpha)
        public struct AsyncIterator: AsyncIteratorProtocol {
            private let storage: IteratorStorage

            fileprivate init(_ stream: FusionRuntime.TransportBootstrapInbox.EventStream) {
                storage = IteratorStorage(stream.makeAsyncIterator())
            }

            @_spi(MosaicPrivateAlpha)
            public mutating func next() async throws -> Element? {
                try await storage.next()
            }
        }

        // Keep the dependency's generic iterator layout inside this module.
        // This preserves pull-based iteration without a forwarding task or buffer.
        private final class IteratorStorage {
            private var iterator: FusionRuntime.TransportBootstrapInbox.EventStream.Iterator

            init(_ iterator: FusionRuntime.TransportBootstrapInbox.EventStream.Iterator) {
                self.iterator = iterator
            }

            func next() async throws -> Element? {
                do {
                    return try await iterator.next().map(Element.init)
                } catch let cancellation as CancellationError {
                    throw cancellation
                } catch {
                    throw OpalBase.Account.MosaicPrivateAlphaRuntime
                        .Failure(error)
                }
            }
        }

        private final class StreamStorage: Sendable {
            let stream: FusionRuntime.TransportBootstrapInbox.EventStream

            init(_ stream: FusionRuntime.TransportBootstrapInbox.EventStream) {
                self.stream = stream
            }
        }

        private let storage: StreamStorage

        init(
            _ stream: OpalFusion.MosaicPrivateAlphaRuntime
                .TransportBootstrapInbox.EventStream
        ) {
            storage = StreamStorage(stream)
        }

        @_spi(MosaicPrivateAlpha)
        public func makeAsyncIterator() -> AsyncIterator {
            .init(storage.stream)
        }
    }

    /// Base-owned wrapper over the package-authenticated exact-three-source bootstrap inbox.
    @_spi(MosaicPrivateAlpha)
    public actor TransportBootstrapInbox {
        @_spi(MosaicPrivateAlpha)
        public typealias EventStream = TransportBootstrapEventStream

        private let inbox: OpalFusion.MosaicPrivateAlphaRuntime
            .TransportBootstrapInbox

        init(
            _ inbox: OpalFusion.MosaicPrivateAlphaRuntime
                .TransportBootstrapInbox
        ) {
            self.inbox = inbox
        }

        @_spi(MosaicPrivateAlpha)
        public func start() async throws -> EventStream {
            do {
                return .init(try await inbox.start())
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw Failure(error)
            }
        }

        @_spi(MosaicPrivateAlpha)
        public func stop() async {
            await inbox.stop()
        }

        @_spi(MosaicPrivateAlpha)
        public func waitForTermination() async {
            await inbox.waitForTermination()
        }
    }
}

extension OpalBase.Account.MosaicPrivateAlphaRuntime
    .TransportBootstrapPublication {
    /// Publishes this exact persisted event only to endpoints lacking durable acceptance.
    @_spi(MosaicPrivateAlpha)
    public func publish(
        using capabilities: OpalBase.Account.MosaicPrivateAlphaRuntime
            .TransportBootstrapPublicationCapabilities
    ) async throws -> OpalBase.Account.MosaicPrivateAlphaRuntime
        .TransportBootstrapPublicationReceipt {
        do {
            return .init(
                try await fusionPublication.publish(
                    using: capabilities.fusionCapabilities()
                )
            )
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            throw OpalBase.Account.MosaicPrivateAlphaRuntime.Failure(error)
        }
    }
}
#endif
