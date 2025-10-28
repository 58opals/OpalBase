// Network+FulcrumSession.swift

import Foundation
import SwiftFulcrum

extension Network {
    public actor FulcrumSession {
        public enum Error: Swift.Error {
            case sessionAlreadyStarted
            case sessionNotStarted
            case unsupportedServerAddress
        }
        
        public let configuration: SwiftFulcrum.Fulcrum.Configuration
        public private(set) var preferredServerAddress: URL?
        public private(set) var candidateServerAddresses: [URL]
        public private(set) var activeServerAddress: URL?
        
        public enum Event: Sendable, Equatable {
            case didActivateServer(URL)
            case didDeactivateServer(URL)
            case didPromoteServer(URL)
            case didDemoteServer(URL)
            case didFailToConnectToServer(URL, failureDescription: String)
        }
        
        private var fulcrum: SwiftFulcrum.Fulcrum?
        private var isSessionRunning = false
        
        private var eventContinuations: [UUID: AsyncStream<Event>.Continuation] = .init()
        
        public init(serverAddress: URL? = nil,
                    configuration: SwiftFulcrum.Fulcrum.Configuration = .init()) async throws {
            self.configuration = configuration
            self.preferredServerAddress = serverAddress
            self.candidateServerAddresses = Self.makeCandidateServerAddresses(from: serverAddress,
                                                                              configuration: configuration)
            self.activeServerAddress = nil
        }
        
        public var isRunning: Bool { isSessionRunning }
        
        public func makeEventStream() -> AsyncStream<Event> {
            AsyncStream { continuation in
                self.registerEventContinuation(continuation)
            }
        }
        
        private func registerEventContinuation(_ continuation: AsyncStream<Event>.Continuation) {
            let identifier = UUID()
            
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.removeEventContinuation(for: identifier) }
            }
            
            eventContinuations[identifier] = continuation
        }
        
        private func removeEventContinuation(for identifier: UUID) {
            eventContinuations.removeValue(forKey: identifier)
        }
        
        public func start() async throws {
            guard !isSessionRunning else { throw Error.sessionAlreadyStarted }
            
            if let currentFulcrum = fulcrum {
                do {
                    try await currentFulcrum.start()
                    isSessionRunning = true
                    if activeServerAddress == nil {
                        setActiveServerAddress(candidateServerAddresses.first)
                    }
                    return
                } catch {
                    await currentFulcrum.stop()
                    self.fulcrum = nil
                    setActiveServerAddress(nil)
                }
            }
            
            try await startUsingCandidateServers()
        }
        
        public func stop() async throws {
            guard isSessionRunning else { throw Error.sessionNotStarted }
            
            await fulcrum?.stop()
            isSessionRunning = false
            fulcrum = nil
            setActiveServerAddress(nil)
        }
        
        public func reconnect() async throws {
            try ensureSessionIsRunning()
            guard let fulcrum else {
                isSessionRunning = false
                throw Error.sessionNotStarted
            }
            
            do {
                try await fulcrum.reconnect()
            } catch {
                await fulcrum.stop()
                isSessionRunning = false
                self.fulcrum = nil
                
                if let activeServerAddress {
                    emitEvent(.didFailToConnectToServer(activeServerAddress,
                                                        failureDescription: error.localizedDescription))
                    demoteCandidate(activeServerAddress)
                    setActiveServerAddress(nil)
                }
                
                try await start()
            }
        }
        
        public func activateServerAddress(_ server: URL) async throws {
            let previousPreferredServerAddress = preferredServerAddress
            let previousCandidateServerAddresses = candidateServerAddresses
            
            preferredServerAddress = server
            candidateServerAddresses = Self.makeCandidateServerAddresses(from: preferredServerAddress,
                                                                         configuration: configuration)
            
            guard candidateServerAddresses.contains(server) else {
                preferredServerAddress = previousPreferredServerAddress
                candidateServerAddresses = previousCandidateServerAddresses
                throw Error.unsupportedServerAddress
            }
            
            if isSessionRunning {
                if activeServerAddress == server {
                    return
                }
                
                if let fulcrum {
                    await fulcrum.stop()
                }
                
                self.fulcrum = nil
                isSessionRunning = false
                setActiveServerAddress(nil)
            }
            
            try await start()
        }
        
        public func submit<RegularResponseResult: JSONRPCConvertible>(
            method: SwiftFulcrum.Method,
            responseType: RegularResponseResult.Type = RegularResponseResult.self,
            options: SwiftFulcrum.Client.Call.Options = .init()
        ) async throws -> SwiftFulcrum.Fulcrum.RPCResponse<RegularResponseResult, Never> {
            try ensureSessionIsRunning()
            guard let fulcrum else { throw Error.sessionNotStarted }
            
            return try await fulcrum.submit(method: method,
                                            responseType: responseType,
                                            options: options)
        }
        
        public func submit<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>(
            method: SwiftFulcrum.Method,
            initialType: Initial.Type = Initial.self,
            notificationType: Notification.Type = Notification.self,
            options: SwiftFulcrum.Client.Call.Options = .init()
        ) async throws -> SwiftFulcrum.Fulcrum.RPCResponse<Initial, Notification> {
            try ensureSessionIsRunning()
            guard let fulcrum else { throw Error.sessionNotStarted }
            
            return try await fulcrum.submit(method: method,
                                            initialType: initialType,
                                            notificationType: notificationType,
                                            options: options)
        }
        
        private func ensureSessionIsRunning() throws {
            guard isSessionRunning else { throw Error.sessionNotStarted }
        }
        
        private func startUsingCandidateServers() async throws {
            if candidateServerAddresses.isEmpty {
                candidateServerAddresses = Self.makeCandidateServerAddresses(from: preferredServerAddress,
                                                                             configuration: configuration)
            }
            
            let serversToAttempt = candidateServerAddresses
            var lastError: Swift.Error?
            
            for server in serversToAttempt {
                do {
                    let instance = try await SwiftFulcrum.Fulcrum(url: server.absoluteString,
                                                                  configuration: configuration)
                    
                    do {
                        try await instance.start()
                        fulcrum = instance
                        isSessionRunning = true
                        promoteCandidate(server)
                        setActiveServerAddress(server)
                        return
                    } catch {
                        await instance.stop()
                        lastError = error
                        emitEvent(.didFailToConnectToServer(server, failureDescription: error.localizedDescription))
                        demoteCandidate(server)
                    }
                } catch {
                    lastError = error
                    emitEvent(.didFailToConnectToServer(server, failureDescription: error.localizedDescription))
                    demoteCandidate(server)
                }
            }
            
            if serversToAttempt.isEmpty {
                let instance = try await SwiftFulcrum.Fulcrum(url: nil, configuration: configuration)
                
                do {
                    try await instance.start()
                    fulcrum = instance
                    isSessionRunning = true
                    return
                } catch {
                    await instance.stop()
                    lastError = error
                }
            }
            
            throw lastError ?? SwiftFulcrum.Fulcrum.Error.transport(.setupFailed)
        }
        
        private func promoteCandidate(_ server: URL) {
            guard let index = candidateServerAddresses.firstIndex(of: server) else { return }
            let candidate = candidateServerAddresses.remove(at: index)
            candidateServerAddresses.insert(candidate, at: candidateServerAddresses.startIndex)
            emitEvent(.didPromoteServer(server))
        }
        
        private func demoteCandidate(_ server: URL) {
            guard let index = candidateServerAddresses.firstIndex(of: server) else { return }
            let candidate = candidateServerAddresses.remove(at: index)
            candidateServerAddresses.append(candidate)
            emitEvent(.didDemoteServer(server))
        }
        
        private func setActiveServerAddress(_ server: URL?) {
            guard activeServerAddress != server else { return }
            
            if let currentAddress = activeServerAddress {
                emitEvent(.didDeactivateServer(currentAddress))
            }
            
            activeServerAddress = server
            
            if let server {
                emitEvent(.didActivateServer(server))
            }
        }
        
        private func emitEvent(_ event: Event) {
            let continuations = Array(eventContinuations.values)
            
            for continuation in continuations {
                continuation.yield(event)
            }
        }
        
        private static func makeCandidateServerAddresses(from serverAddress: URL?,
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
