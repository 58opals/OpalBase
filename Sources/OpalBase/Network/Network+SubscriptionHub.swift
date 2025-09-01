// Network+SubscriptionHub.swift

import Foundation

extension Network {
    public actor SubscriptionHub<Hash: Hashable & Sendable> {
        public typealias SubscribeHandler = @Sendable ([Hash]) async throws -> Void
        public typealias UnsubscribeHandler = @Sendable ([Hash]) async throws -> Void
        
        public struct Update: Sendable {
            public let hash: Hash
            public let status: String
            public init(hash: Hash, status: String) {
                self.hash = hash
                self.status = status
            }
        }
        
        private let subscribeHandler: SubscribeHandler
        private let unsubscribeHandler: UnsubscribeHandler
        private var counts: [Hash: Int] = [:]
        private var pending: Set<Hash> = []
        private var isConnected = true
        private var flushTask: Task<Void, Never>?
        private let batchInterval: Duration
        
        private var continuation: AsyncStream<Update>.Continuation
        public let updates: AsyncStream<Update>
        
        public init(
            batchInterval: Duration = .milliseconds(50),
            subscribe: @escaping SubscribeHandler,
            unsubscribe: @escaping UnsubscribeHandler
        ) {
            self.batchInterval = batchInterval
            self.subscribeHandler = subscribe
            self.unsubscribeHandler = unsubscribe
            var cont: AsyncStream<Update>.Continuation!
            self.updates = AsyncStream<Update> { continuation in
                cont = continuation
            }
            self.continuation = cont
        }
        
        public func subscribe(to hash: Hash) async throws {
            if let existing = counts[hash] {
                counts[hash] = existing + 1
                return
            }
            counts[hash] = 1
            pending.insert(hash)
            scheduleFlush()
        }
        
        public func unsubscribe(from hash: Hash) async throws {
            guard let existing = counts[hash] else { return }
            if existing > 1 {
                counts[hash] = existing - 1
                return
            }
            counts[hash] = nil
            guard isConnected else { return }
            do {
                try await unsubscribeHandler([hash])
            } catch {
                throw Error.unsubscribeFailed(error)
            }
        }
        
        public func handle(update: Update) {
            continuation.yield(update)
        }
        
        public func setConnection(active: Bool) async {
            guard isConnected != active else { return }
            isConnected = active
            if active {
                pending.formUnion(counts.keys)
                scheduleFlush()
            } else {
                flushTask?.cancel()
                flushTask = nil
            }
        }
        
        private func scheduleFlush() {
            guard flushTask == nil else { return }
            flushTask = Task { [batchInterval] in
                try? await Task.sleep(for: batchInterval)
                await flush()
            }
        }
        
        private func flush() async {
            flushTask = nil
            guard isConnected, !pending.isEmpty else {
                pending.removeAll()
                return
            }
            let hashes = Array(pending)
            pending.removeAll()
            do {
                try await subscribeHandler(hashes)
            } catch {
                if let first = hashes.first {
                    continuation.yield(Update(hash: first, status: "error: \(error.localizedDescription)"))
                }
            }
        }
    }
}

extension Network.SubscriptionHub {
    public enum Error: Swift.Error, Sendable {
        case subscribeFailed(Swift.Error)
        case unsubscribeFailed(Swift.Error)
    }
}

extension Network.SubscriptionHub.Error: Equatable {
    public static func == (lhs: Network.SubscriptionHub<Hash>.Error, rhs: Network.SubscriptionHub<Hash>.Error) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}
