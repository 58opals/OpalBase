// Lifecycle+Coordinator.swift

import Foundation

extension Lifecycle {
    public actor Coordinator<Value: Sendable> {
        public struct Hooks: Sendable {
            public let start: @Sendable () async throws -> AsyncThrowingStream<Value, Swift.Error>
            public let suspend: @Sendable () async throws -> Void
            public let resume: @Sendable () async throws -> Void
            public let shutdown: @Sendable () async throws -> Void
            
            public init(start: @escaping @Sendable () async throws -> AsyncThrowingStream<Value, Swift.Error>,
                        suspend: @escaping @Sendable () async throws -> Void,
                        resume: @escaping @Sendable () async throws -> Void,
                        shutdown: @escaping @Sendable () async throws -> Void) {
                self.start = start
                self.suspend = suspend
                self.resume = resume
                self.shutdown = shutdown
            }
        }
        
        public enum Error: Swift.Error {
            case alreadyRunning
            case noSources
            case sourceFailure(label: String, underlying: Swift.Error)
        }
        
        private struct Source {
            let label: String
            let hooks: Hooks
            var tasks: [Task<Void, Never>]
        }
        
        private var sources: [UUID: Source] = .init()
        private var activeSourceIDs: Set<UUID> = .init()
        private var isActive = false
        private var isSuspended = false
        private var continuation: AsyncThrowingStream<Value, Swift.Error>.Continuation?
        
        public init() {}
        
        public func register(label: String, hooks: Hooks) -> UUID {
            let identifier = UUID()
            sources[identifier] = Source(label: label, hooks: hooks, tasks: .init())
            return identifier
        }
        
        public func unregister(_ identifier: UUID) {
            guard !isActive else { return }
            sources.removeValue(forKey: identifier)
        }
        
        public func start() async throws -> AsyncThrowingStream<Value, Swift.Error> {
            guard !isActive else { throw Error.alreadyRunning }
            guard !sources.isEmpty else { throw Error.noSources }
            
            var streams: [UUID: AsyncThrowingStream<Value, Swift.Error>] = .init()
            for (identifier, source) in sources {
                do {
                    let stream = try await source.hooks.start()
                    streams[identifier] = stream
                } catch {
                    throw Error.sourceFailure(label: source.label, underlying: error)
                }
            }
            
            isActive = true
            isSuspended = false
            activeSourceIDs = .init(streams.keys)
            
            return AsyncThrowingStream { continuation in
                self.continuation = continuation
                continuation.onTermination = { _ in
                    Task { await self.shutdown() }
                }
                
                for (identifier, stream) in streams {
                    self.launchForwarder(stream: stream, identifier: identifier)
                }
            }
        }
        
        public func suspend() async throws {
            guard isActive, !isSuspended else { return }
            
            for identifier in activeSourceIDs {
                guard let source = sources[identifier] else { continue }
                do {
                    try await source.hooks.suspend()
                } catch {
                    let failure = Error.sourceFailure(label: source.label, underlying: error)
                    continuation?.finish(throwing: failure)
                    continuation = nil
                    await cancelRemaining(excluding: identifier)
                    throw failure
                }
            }
            
            isSuspended = true
        }
        
        public func resume() async throws {
            guard isActive, isSuspended else { return }
            
            for identifier in activeSourceIDs {
                guard let source = sources[identifier] else { continue }
                do {
                    try await source.hooks.resume()
                } catch {
                    let failure = Error.sourceFailure(label: source.label, underlying: error)
                    continuation?.finish(throwing: failure)
                    continuation = nil
                    await cancelRemaining(excluding: identifier)
                    throw failure
                }
            }
            
            isSuspended = false
        }
        
        public func shutdown() async {
            guard isActive else { return }
            isActive = false
            isSuspended = false
            activeSourceIDs.removeAll()
            
            let localContinuation = continuation
            continuation = nil
            
            await cancelRemaining(excluding: nil)
            localContinuation?.finish()
        }
    }
}

extension Lifecycle.Coordinator {
    func launchForwarder(stream: AsyncThrowingStream<Value, Swift.Error>, identifier: UUID) {
        var source = sources[identifier]
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await value in stream {
                    await self.emit(value)
                }
                await self.completeSource(identifier: identifier, error: nil)
            } catch {
                await self.completeSource(identifier: identifier, error: error)
            }
        }
        
        source?.tasks.append(task)
        if let source { sources[identifier] = source }
    }
    
    func emit(_ value: Value) {
        continuation?.yield(value)
    }
    
    func completeSource(identifier: UUID, error: Swift.Error?) async {
        guard var source = sources[identifier] else { return }
        
        for task in source.tasks { task.cancel() }
        source.tasks.removeAll()
        sources[identifier] = source
        
        do {
            try await source.hooks.shutdown()
        } catch {
            let failure = Error.sourceFailure(label: source.label, underlying: error)
            continuation?.finish(throwing: failure)
            continuation = nil
            await cancelRemaining(excluding: identifier)
            return
        }
        
        if let error {
            let failure = Error.sourceFailure(label: source.label, underlying: error)
            continuation?.finish(throwing: failure)
            continuation = nil
            await cancelRemaining(excluding: identifier)
            return
        }
        
        activeSourceIDs.remove(identifier)
        if activeSourceIDs.isEmpty {
            let localContinuation = continuation
            continuation = nil
            await cancelRemaining(excluding: identifier)
            localContinuation?.finish()
        }
    }
    
    func cancelRemaining(excluding excludedIdentifier: UUID?) async {
        for (identifier, var source) in sources {
            if let excludedIdentifier, excludedIdentifier == identifier { continue }
            for task in source.tasks { task.cancel() }
            source.tasks.removeAll()
            sources[identifier] = source
            do {
                try await source.hooks.shutdown()
            } catch { }
        }
        
        activeSourceIDs.removeAll()
        isActive = false
        isSuspended = false
    }
}
