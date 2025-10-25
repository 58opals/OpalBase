// Network+Wallet+SubscriptionHub+State.swift

import Foundation

extension Network.Wallet.SubscriptionHub {
    struct State {
        var consumerIdentifiers: Set<UUID> = .init()
        var streamTask: Task<Void, Never>?
        var cancelAction: (@Sendable () async -> Void)?
        var flushTask: Task<Void, Never>?
        var queue: AddressQueue = .init()
    }
}
