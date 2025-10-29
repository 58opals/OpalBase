// Network+FulcrumSession.swift

import Foundation
import SwiftFulcrum

extension Network {
    public actor FulcrumSession {
        public enum Error: Swift.Error {
            case sessionAlreadyStarted
            case sessionNotStarted
            case unsupportedServerAddress
            case unexpectedResponse(SwiftFulcrum.Method)
            case subscriptionNotFound
            case failedToRestoreSubscription(Swift.Error)
        }
        
        public enum Event: Sendable, Equatable {
            case didActivateServer(URL)
            case didDeactivateServer(URL)
            case didPromoteServer(URL)
            case didDemoteServer(URL)
            case didFailToConnectToServer(URL, failureDescription: String)
        }
        
        public let configuration: SwiftFulcrum.Fulcrum.Configuration
        public var preferredServerAddress: URL?
        public var candidateServerAddresses: [URL]
        public var activeServerAddress: URL?
        
        public var isRunning: Bool { isSessionRunning }
        
        var fulcrum: SwiftFulcrum.Fulcrum?
        var isSessionRunning = false
        
        var eventContinuations: [UUID: AsyncStream<Event>.Continuation] = .init()
        var streamingCallDescriptors: [UUID: any AnyStreamingCallDescriptor] = .init()
        
        public init(serverAddress: URL? = nil,
                    configuration: SwiftFulcrum.Fulcrum.Configuration = .init()) async throws {
            self.configuration = configuration
            self.preferredServerAddress = serverAddress
            self.candidateServerAddresses = Self.makeCandidateServerAddresses(from: serverAddress,
                                                                              configuration: configuration)
            self.activeServerAddress = nil
        }
        
        public func makeEventStream() -> AsyncStream<Event> {
            AsyncStream { continuation in
                registerEventContinuation(continuation)
            }
        }
        
        func registerEventContinuation(_ continuation: AsyncStream<Event>.Continuation) {
            let identifier = UUID()
            
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.removeEventContinuation(for: identifier) }
            }
            
            eventContinuations[identifier] = continuation
        }
        
        func removeEventContinuation(for identifier: UUID) {
            eventContinuations.removeValue(forKey: identifier)
        }
        
        func emitEvent(_ event: Event) {
            let continuations = Array(eventContinuations.values)
            
            for continuation in continuations {
                continuation.yield(event)
            }
        }
        
        func ensureSessionIsRunning() throws {
            guard isSessionRunning else { throw Error.sessionNotStarted }
        }
        
        static func makeCandidateServerAddresses(from serverAddress: URL?,
                                                 configuration: SwiftFulcrum.Fulcrum.Configuration) -> [URL] {
            var result: [URL] = .init()
            var seen: Set<URL> = .init()
            
            func append(_ url: URL) {
                guard let scheme = url.scheme?.lowercased(), scheme == "ws" || scheme == "wss" else { return }
                guard seen.insert(url).inserted else { return }
                result.append(url)
            }
            
            if let serverAddress {
                append(serverAddress)
            }
            
            if let bootstrapServers = configuration.bootstrapServers {
                bootstrapServers.forEach(append)
            }
            
            let shouldUseBundledServers = serverAddress == nil && (configuration.bootstrapServers?.isEmpty ?? true)
            
            if shouldUseBundledServers,
               let bundledServers = try? SwiftFulcrum.WebSocket.Server.decodeBundledServers() {
                bundledServers.forEach(append)
            }
            
            return result
        }
    }
}
