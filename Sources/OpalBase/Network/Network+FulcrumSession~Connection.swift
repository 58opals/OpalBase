// Network+FulcrumSession~Connection.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
    public func start() async throws {
        guard !isSessionRunning else { throw Error.sessionAlreadyStarted }
        
        if let currentFulcrum = fulcrum {
            do {
                try await currentFulcrum.start()
                isSessionRunning = true
                if activeServerAddress == nil {
                    setActiveServerAddress(candidateServerAddresses.first)
                }
                try await restoreStreamingSubscriptions(using: currentFulcrum)
                return
            } catch {
                await prepareStreamingCallsForRestart()
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
        await cancelAllStreamingCalls()
    }
    
    public func reconnect() async throws {
        try ensureSessionIsRunning()
        guard let fulcrum else {
            isSessionRunning = false
            throw Error.sessionNotStarted
        }
        
        do {
            try await fulcrum.reconnect()
            try await restoreStreamingSubscriptions(using: fulcrum)
        } catch {
            await prepareStreamingCallsForRestart()
            
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
            
            await prepareStreamingCallsForRestart()
            setActiveServerAddress(nil)
        }
        
        try await start()
    }
    
    func resetFulcrumForRestart() async {
        if let currentFulcrum = fulcrum {
            await currentFulcrum.stop()
            fulcrum = nil
        }
        isSessionRunning = false
    }
    
    private func startUsingCandidateServers() async throws {
        await resetFulcrumForRestart()
        
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
                    do {
                        try await restoreStreamingSubscriptions(using: instance)
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
                        await prepareStreamingCallsForRestart()
                    }
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
                do {
                    try await restoreStreamingSubscriptions(using: instance)
                    fulcrum = instance
                    isSessionRunning = true
                    return
                } catch {
                    await instance.stop()
                    lastError = error
                    await prepareStreamingCallsForRestart()
                }
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
}
