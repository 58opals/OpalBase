// Network+Wallet+SubscriptionHub~Persistence.swift

import Foundation

extension Network.Wallet.SubscriptionHub {
    struct StorageBackfillAdapter: Persistence, ReplayAdapter, Sendable {
        let repository: Storage.Repository.Subscriptions
        
        init(repository: Storage.Repository.Subscriptions) {
            self.repository = repository
        }
        
        func loadState(for address: Address) async throws -> PersistenceState? {
            guard let row = try await repository.byAddress(address.string) else { return nil }
            return PersistenceState(address: address, activationFlag: row.isActive, lastStatus: row.lastStatus)
        }
        
        func persist(_ state: PersistenceState) async throws {
            try await repository.upsert(address: state.address.string,
                                        isActive: state.activationFlag,
                                        lastStatus: state.lastStatus)
        }
        
        func deactivate(address: Address, lastStatus: String?) async throws {
            try await repository.upsert(address: address.string,
                                        isActive: false,
                                        lastStatus: lastStatus)
        }
        
        func replay(for address: Address, lastStatus: String?) -> AsyncThrowingStream<Notification.Event, Swift.Error> {
            AsyncThrowingStream { continuation in
                Task {
                    do {
                        let status: String?
                        if let lastStatus {
                            status = lastStatus
                        } else {
                            status = try await repository.byAddress(address.string)?.lastStatus
                        }
                        if let status {
                            continuation.yield(
                                Notification.Event(address: address,
                                                   status: status,
                                                   replayFlag: true,
                                                   sequence: 0)
                            )
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }
}
