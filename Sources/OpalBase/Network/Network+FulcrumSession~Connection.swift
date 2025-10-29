// Network+FulcrumSession~Connection.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
    public func start() async throws {
        guard state == .stopped else { throw Error.sessionAlreadyStarted }
        
        if try await restartExistingFulcrumIfPossible() { return }
        await resetFulcrumForRestart()
        do {
            try await startUsingCandidateServers()
        } catch {
            state = .stopped
            throw error
        }
    }
    
    public func stop() async throws {
        guard state == .running || state == .restoring else { throw Error.sessionNotStarted }
        
        await cancelAllStreamingCalls()
        await resetFulcrumForRestart()
        setActiveServerAddress(nil)
        await cancelAllStreamingCalls()
        state = .stopped
    }
    
    public func reconnect() async throws {
        try ensureSessionReady()
        guard let fulcrum else {
            state = .stopped
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
        let wasOperational = isOperational
        let previousActiveServerAddress = activeServerAddress
        
        preferredServerAddress = server
        candidateServerAddresses = Self.makeCandidateServerAddresses(from: preferredServerAddress,
                                                                     configuration: configuration)
        
        guard candidateServerAddresses.contains(server) else {
            preferredServerAddress = previousPreferredServerAddress
            candidateServerAddresses = previousCandidateServerAddresses
            throw Error.unsupportedServerAddress
        }
        
        if wasOperational {
            if previousActiveServerAddress == server {
                return
            }
            
            await prepareStreamingCallsForRestart()
            setActiveServerAddress(nil)
        }
        
        do {
            try await start()
        } catch {
            preferredServerAddress = previousPreferredServerAddress
            candidateServerAddresses = previousCandidateServerAddresses
            
            if wasOperational {
                do {
                    try await start()
                } catch {}
            }
            
            throw error
        }
    }
    
    func resetFulcrumForRestart() async {
        if let currentFulcrum = fulcrum {
            await currentFulcrum.stop()
            fulcrum = nil
        }
    }
    
    private func startUsingCandidateServers() async throws {
        refreshCandidateServerAddressesIfNeeded()
        
        let serversToAttempt = makeServersToAttempt()
        var lastError: Swift.Error?
        
        for server in serversToAttempt {
            do {
                state = .restoring
                try await connectAndActivateServer(server)
                return
            } catch {
                state = .stopped
                lastError = error
            }
        }
        
        throw lastError ?? SwiftFulcrum.Fulcrum.Error.transport(.setupFailed)
    }
    
    private func makeServersToAttempt() -> [URL?] {
        var attempts = candidateServerAddresses.map(Optional.some)
        
        if attempts.isEmpty {
            attempts.append(nil)
        } else if preferredServerAddress == nil {
            attempts.append(nil)
        }
        
        return attempts
    }
    
    private func restartExistingFulcrumIfPossible() async throws -> Bool {
        guard let currentFulcrum = fulcrum else { return false }
        
        do {
            state = .restoring
            try await currentFulcrum.start()
            if activeServerAddress == nil {
                setActiveServerAddress(candidateServerAddresses.first)
            }
            try await restoreStreamingSubscriptions(using: currentFulcrum)
            state = .running
            return true
        } catch {
            state = .stopped
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
        if preferredServerAddress == server { return }
        guard let index = candidateServerAddresses.firstIndex(of: server) else { return }
        let candidate = candidateServerAddresses.remove(at: index)
        candidateServerAddresses.append(candidate)
        emitEvent(.didDemoteServer(server))
    }
    
    func setActiveServerAddress(_ server: URL?) {
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
        
        fulcrum = instance
        do {
            try await instance.start()
            try await restoreStreamingSubscriptions(using: instance)
            state = .running
        } catch {
            state = .stopped
            fulcrum = nil
            await instance.stop()
            await handleConnectionFailure(for: server,
                                          error: error,
                                          shouldForceStreamingPreparation: isStreamingRestorationFailure(error))
            throw error
        }
        
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
        state = .stopped
        
        setActiveServerAddress(nil)
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
