// Network~Account~Sync~State.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
    typealias ScriptHashSubscription = Subscription<SwiftFulcrum.Response.Result.Blockchain.ScriptHash.Subscribe, SwiftFulcrum.Response.Result.Blockchain.ScriptHash.SubscribeNotification>
    
    struct AccountSynchronizationState {
        var account: Account
        var callOptions: SwiftFulcrum.Client.Call.Options
        var addressContexts: [String: AddressContext]
    }
    
    struct AddressContext {
        var address: Address
        var usage: DerivationPath.Usage
        var scriptHash: String
        var subscription: ScriptHashSubscription
        var updateTask: Task<Void, Never>?
        var latestStatus: String?
    }
}

extension Network.FulcrumSession {
    func ensureSynchronizationState(
        for account: Account,
        options: SwiftFulcrum.Client.Call.Options
    ) -> AccountSynchronizationState {
        let identifier = account.id
        var state = accountSynchronizationStates[identifier]
        ?? AccountSynchronizationState(account: account,
                                       callOptions: options,
                                       addressContexts: [:])
        state.account = account
        state.callOptions = options
        accountSynchronizationStates[identifier] = state
        return state
    }
    
    func synchronizationState(for accountIdentifier: Data) -> AccountSynchronizationState? {
        accountSynchronizationStates[accountIdentifier]
    }
    
    func updateSynchronizationState(
        for accountIdentifier: Data,
        _ body: (inout AccountSynchronizationState) -> Void
    ) {
        guard var state = accountSynchronizationStates[accountIdentifier] else { return }
        body(&state)
        accountSynchronizationStates[accountIdentifier] = state
    }
    
    func updateScriptHashContext(
        for accountIdentifier: Data,
        scriptHash: String,
        _ body: (inout AddressContext) -> Void
    ) {
        updateSynchronizationState(for: accountIdentifier) { state in
            guard var context = state.addressContexts[scriptHash] else { return }
            body(&context)
            state.addressContexts[scriptHash] = context
        }
    }
    
    func removeSynchronizationState(for accountIdentifier: Data) -> AccountSynchronizationState? {
        accountSynchronizationStates.removeValue(forKey: accountIdentifier)
    }
    
    func cancelAddressContexts<S: Sequence>(
        _ contexts: S
    ) async where S.Element == AddressContext {
        for context in contexts {
            context.updateTask?.cancel()
            await context.subscription.cancel()
        }
    }
}
