// Network+FulcrumSession.swift

import Foundation
import SwiftFulcrum

extension Network {
    public actor FulcrumSession {
        public enum Error: Swift.Error {
            case sessionAlreadyStarted
            case sessionNotStarted
        }
        
        public let configuration: SwiftFulcrum.Fulcrum.Configuration
        public let serverAddress: URL?
        
        private var fulcrum: SwiftFulcrum.Fulcrum?
        private var isSessionRunning = false
        
        private var candidateServers: [URL]
        private var activeServerAddress: URL?
        
        public init(serverAddress: URL? = nil,
                    configuration: SwiftFulcrum.Fulcrum.Configuration = .init()) async throws {
            self.configuration = configuration
            self.serverAddress = serverAddress
            self.candidateServers = Self.makeCandidateServers(from: serverAddress,
                                                              configuration: configuration)
        }
        
        public var isRunning: Bool { isSessionRunning }
        
        public func start() async throws {
            guard !isSessionRunning else { return }
            
            if let currentFulcrum = fulcrum {
                do {
                    try await currentFulcrum.start()
                    isSessionRunning = true
                    if activeServerAddress == nil {
                        activeServerAddress = candidateServers.first
                    }
                    return
                } catch {
                    await currentFulcrum.stop()
                    self.fulcrum = nil
                    activeServerAddress = nil
                }
            }
            
            try await startUsingCandidateServers()
        }
        
        public func stop() async {
            guard isSessionRunning else { return }
            
            await fulcrum?.stop()
            isSessionRunning = false
            fulcrum = nil
            activeServerAddress = nil
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
                    demoteCandidate(activeServerAddress)
                    self.activeServerAddress = nil
                }
                
                try await start()
            }
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
            if candidateServers.isEmpty {
                candidateServers = Self.makeCandidateServers(from: serverAddress,
                                                             configuration: configuration)
            }
            
            let serversToAttempt = candidateServers
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
                        activeServerAddress = server
                        return
                    } catch {
                        await instance.stop()
                        lastError = error
                        demoteCandidate(server)
                    }
                } catch {
                    lastError = error
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
            guard let index = candidateServers.firstIndex(of: server) else { return }
            let candidate = candidateServers.remove(at: index)
            candidateServers.insert(candidate, at: candidateServers.startIndex)
        }
        
        private func demoteCandidate(_ server: URL) {
            guard let index = candidateServers.firstIndex(of: server) else { return }
            let candidate = candidateServers.remove(at: index)
            candidateServers.append(candidate)
        }
        
        private static func makeCandidateServers(from serverAddress: URL?,
                                                 configuration: SwiftFulcrum.Fulcrum.Configuration) -> [URL] {
            var result: [URL] = []
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
            
            if let bundledServers = try? SwiftFulcrum.WebSocket.Server.decodeBundledServers() {
                bundledServers.forEach(append)
            }
            
            return result
        }
    }
}
