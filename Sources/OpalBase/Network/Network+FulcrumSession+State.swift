// Network+FulcrumSession+State.swift

import Foundation

extension Network.FulcrumSession {
    public enum State: Sendable, Equatable {
        case stopped
        case restoring
        case running
    }
}

extension Network.FulcrumSession {
    func updateState(_ state: State) {
        self.state = state
    }
}

extension Network.FulcrumSession {
    func recordStart(using server: URL?) {
        pendingFallbackOrigin = nil
        emitEvent(.didStart(server))
    }
    
    func recordReconnect(using server: URL?) {
        emitEvent(.didReconnect(server))
    }
    
    func prepareForFallback(from server: URL) {
        pendingFallbackOrigin = server
    }
    
    func recordFallbackIfNeeded(to server: URL?) {
        guard let origin = pendingFallbackOrigin else { return }
        pendingFallbackOrigin = nil
        guard origin != server else { return }
        emitEvent(.didFallback(from: origin, to: server))
    }
}
