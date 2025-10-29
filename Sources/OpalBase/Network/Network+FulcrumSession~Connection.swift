// Network+FulcrumSession~Connection.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
    public func start() async throws {
        guard !isSessionRunning else { throw Error.sessionAlreadyStarted }
        
        if try await restartExistingFulcrumIfPossible() { return }
        await resetFulcrumForRestart()
        try await startUsingCandidateServers()
    }
    
    public func stop() async throws {
        guard isSessionRunning else { throw Error.sessionNotStarted }
        
        await resetFulcrumForRestart()
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
            await handleConnectionFailure(for: activeServerAddress,
                                          error: error,
                                          shouldForceStreamingPreparation: true)
            setActiveServerAddress(nil)
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
        refreshCandidateServerAddressesIfNeeded()
        
        let serversToAttempt = makeServersToAttempt()
        var lastError: Swift.Error?
        
        for server in serversToAttempt {
            do {
                try await connectAndActivateServer(server)
                return
            } catch {
                lastError = error
            }
        }
        
        throw lastError ?? SwiftFulcrum.Fulcrum.Error.transport(.setupFailed)
    }
    
    private func makeServersToAttempt() -> [URL?] {
        let servers = candidateServerAddresses
        guard !servers.isEmpty else { return [nil] }
        return servers.map(Optional.some)
    }
    
    private func restartExistingFulcrumIfPossible() async throws -> Bool {
        guard let currentFulcrum = fulcrum else { return false }
        
        do {
            try await currentFulcrum.start()
            isSessionRunning = true
            if activeServerAddress == nil {
                setActiveServerAddress(candidateServerAddresses.first)
            }
            try await restoreStreamingSubscriptions(using: currentFulcrum)
            return true
        } catch {
            await prepareStreamingCallsForRestart()
            setActiveServerAddress(nil)
            return false
        }
    }
    
    private func refreshCandidateServerAddressesIfNeeded() {
        guard candidateServerAddresses.isEmpty else { return }
        
        candidateServerAddresses = Self.makeCandidateServerAddresses(from: preferredServerAddress,
                                                                     configuration: configuration)
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
    
    private func connectAndActivateServer(_ server: URL?) async throws {
        try await connect(to: server) {
            if let server { promoteCandidate(server) }
            setActiveServerAddress(server)
        }
    }
    
    private func connect(to server: URL?, onSuccess: () -> Void) async throws {
        let instance = try await makeFulcrum(for: server)
        
        do {
            try await instance.start()
            try await restoreStreamingSubscriptions(using: instance)
        } catch {
            await instance.stop()
            await handleConnectionFailure(for: server, error: error, shouldForceStreamingPreparation: isStreamingRestorationFailure(error))
            throw error
        }
        
        fulcrum = instance
        isSessionRunning = true
        onSuccess()
    }
    
    private func makeFulcrum(for server: URL?) async throws -> SwiftFulcrum.Fulcrum {
        do {
            return try await SwiftFulcrum.Fulcrum(url: server?.absoluteString, configuration: configuration)
        } catch {
            await handleConnectionFailure(for: server, error: error)
            throw error
        }
    }
    
    private func handleConnectionFailure(for server: URL?,
                                         error: Swift.Error,
                                         shouldForceStreamingPreparation: Bool = false) async {
        if let server {
            emitEvent(.didFailToConnectToServer(server, failureDescription: error.localizedDescription))
            demoteCandidate(server)
        }
        
        if shouldForceStreamingPreparation || isStreamingRestorationFailure(error) {
            await prepareStreamingCallsForRestart()
        }
    }
    
    private func isStreamingRestorationFailure(_ error: Swift.Error) -> Bool {
        guard let sessionError = error as? Network.FulcrumSession.Error else { return false }
        if case .failedToRestoreSubscription = sessionError { return true }
        return false
    }
}
