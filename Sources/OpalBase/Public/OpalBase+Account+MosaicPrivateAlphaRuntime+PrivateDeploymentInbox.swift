// OpalBase+Account+MosaicPrivateAlphaRuntime+PrivateDeploymentInbox.swift

#if os(macOS)
import Foundation
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// A canonical formation envelope with its local receipt time.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentInboundEvent: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let payloadKind: UInt8
        @_spi(MosaicPrivateAlpha) public let event: PrivateDeploymentEvent

        init(_ value: FusionRuntime.PrivateDeploymentInbox.Inbound) {
            payloadKind = value.payloadKind
            event = .init(canonicalEventBytes: value.event.canonicalEventBytes,
                          acceptedAtUnixSeconds: value.event.acceptedAtUnixSeconds)
        }
    }

    /// Pull-based projection; no forwarding task, extra buffer or protocol parser.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentEventStream: AsyncSequence, Sendable {
        @_spi(MosaicPrivateAlpha)
        public typealias Element = PrivateDeploymentInboundEvent

        @_spi(MosaicPrivateAlpha)
        public struct AsyncIterator: AsyncIteratorProtocol {
            private let storage: IteratorStorage

            fileprivate init(_ stream: FusionRuntime.PrivateDeploymentInbox.EventStream) {
                storage = IteratorStorage(stream.makeAsyncIterator())
            }

            @_spi(MosaicPrivateAlpha)
            public mutating func next() async throws -> Element? {
                try await storage.next()
            }
        }

        // The dependency's generic iterator layout must stay inside Base's
        // framework boundary, including when an optimized app links this SPI.
        private final class IteratorStorage {
            private var iterator: FusionRuntime.PrivateDeploymentInbox.EventStream.Iterator

            init(_ iterator: FusionRuntime.PrivateDeploymentInbox.EventStream.Iterator) {
                self.iterator = iterator
            }

            func next() async throws -> Element? {
                do { return try await iterator.next().map(Element.init) }
                catch let cancellation as CancellationError { throw cancellation }
                catch { throw OpalBase.Account.MosaicPrivateAlphaRuntime.Failure(error) }
            }
        }

        private final class StreamStorage: Sendable {
            let stream: FusionRuntime.PrivateDeploymentInbox.EventStream
            init(_ stream: FusionRuntime.PrivateDeploymentInbox.EventStream) { self.stream = stream }
        }

        private let storage: StreamStorage
        init(_ stream: FusionRuntime.PrivateDeploymentInbox.EventStream) { storage = StreamStorage(stream) }

        @_spi(MosaicPrivateAlpha)
        public func makeAsyncIterator() -> AsyncIterator { .init(storage.stream) }
    }

    /// Exact-three-source public discovery lifecycle, owned by the application.
    @_spi(MosaicPrivateAlpha)
    public actor PrivateDeploymentInbox {
        @_spi(MosaicPrivateAlpha)
        public typealias EventStream = PrivateDeploymentEventStream
        private let inbox: FusionRuntime.PrivateDeploymentInbox

        init(_ inbox: FusionRuntime.PrivateDeploymentInbox) { self.inbox = inbox }

        @_spi(MosaicPrivateAlpha)
        public func start() async throws -> EventStream {
            do { return .init(try await inbox.start()) }
            catch let cancellation as CancellationError { throw cancellation }
            catch { throw Failure(error) }
        }

        @_spi(MosaicPrivateAlpha)
        public func stop() async { await inbox.stop() }
    }
}
#endif
