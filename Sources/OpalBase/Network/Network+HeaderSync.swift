// Network+HeaderSync.swift

import Foundation

extension Network {
    public actor HeaderSync {
        public struct Entry: Sendable {
            public let height: UInt32
            public let header: Block.Header
            public init(height: UInt32, header: Block.Header) {
                self.height = height
                self.header = header
            }
        }
        public typealias SubscribeHandler = @Sendable () async throws -> Void
        
        private let subscribe: SubscribeHandler
        private var lastHeight: UInt32?
        private var continuation: AsyncStream<Entry>.Continuation
        public let headerStream: AsyncStream<Entry>
        
        public init(subscribe: @escaping SubscribeHandler) {
            self.subscribe = subscribe
            var cont: AsyncStream<Entry>.Continuation!
            self.headerStream = AsyncStream<Entry> { continuation in
                cont = continuation
            }
            self.continuation = cont
        }
        
        public func connect() async throws {
            do {
                try await subscribe()
            } catch {
                throw Error.subscribeFailed(error)
            }
        }
        
        public func receive(_ entry: Entry) throws {
            if let lastHeight {
                let expected = lastHeight + 1
                guard entry.height == expected else {
                    throw Error.continuityViolation(expected: expected, actual: entry.height)
                }
            }
            lastHeight = entry.height
            continuation.yield(entry)
        }
    }
}

extension Network.HeaderSync.Entry: Equatable {
    public static func == (lhs: Network.HeaderSync.Entry, rhs: Network.HeaderSync.Entry) -> Bool {
        lhs.height == rhs.height && lhs.header == rhs.header
    }
}

extension Network.HeaderSync {
    public enum Error: Swift.Error, Sendable {
        case subscribeFailed(Swift.Error)
        case continuityViolation(expected: UInt32, actual: UInt32)
    }
}

extension Network.HeaderSync.Error: Equatable {
    public static func == (lhs: Network.HeaderSync.Error, rhs: Network.HeaderSync.Error) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}
