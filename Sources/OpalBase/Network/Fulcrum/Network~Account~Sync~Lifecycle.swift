// Network~Account~Sync~Lifecycle.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
    public func startSynchronization(
        for account: Account,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws {
        try ensureSessionReady(allowRestoring: true)
        await ensureTelemetryInstalled(for: account)
        
        _ = ensureSynchronizationState(for: account, options: options)
        
        try await scanAddressGap(for: account, usage: .receiving, options: options)
        try await scanAddressGap(for: account, usage: .change, options: options)
        try await ensureAddressSubscriptions(for: account, usage: .receiving, options: options)
        try await ensureAddressSubscriptions(for: account, usage: .change, options: options)
    }
    
    public func ensureSynchronization(
        for account: Account,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async {
        do {
            try await startSynchronization(for: account, options: options)
        } catch {}
    }
    
    public func stopSynchronization(for account: Account) async {
        let identifier = account.id
        guard let state = removeSynchronizationState(for: identifier) else { return }
        await cancelAddressContexts(state.addressContexts.values)
    }
    
    func cancelAllAccountSynchronizations() async {
        guard !accountSynchronizationStates.isEmpty else { return }
        let states = accountSynchronizationStates.values.map { $0 }
        accountSynchronizationStates.removeAll()
        for state in states {
            await cancelAddressContexts(state.addressContexts.values)
        }
    }
}
