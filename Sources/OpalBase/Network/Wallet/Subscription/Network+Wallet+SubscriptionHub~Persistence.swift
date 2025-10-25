// Network+Wallet+SubscriptionHub~Persistence.swift

import Foundation

private struct StorageBackfillAdapter: Sendable {
    let repository: Storage.Repository.Subscriptions
    
    func makeDependencies() -> Network.Wallet.SubscriptionHub.Dependencies {
        .init(
            loader: { address in
                do {
                    guard let row = try await repository.byAddress(address.string) else { return nil }
                    return .init(address: address, activationFlag: row.isActive, lastStatus: row.lastStatus)
                } catch {
                    throw Network.Wallet.SubscriptionHub.Dependencies.Error.repository(String(describing: error))
                }
            },
            writer: { state in
                do {
                    try await repository.upsert(address: state.address.string,
                                                isActive: state.activationFlag,
                                                lastStatus: state.lastStatus)
                } catch {
                    throw Network.Wallet.SubscriptionHub.Dependencies.Error.repository(String(describing: error))
                }
            },
            deactivator: { address, lastStatus in
                do {
                    try await repository.upsert(address: address.string,
                                                isActive: false,
                                                lastStatus: lastStatus)
                } catch {
                    throw Network.Wallet.SubscriptionHub.Dependencies.Error.repository(String(describing: error))
                }
            },
            replayFactory: { address, lastStatus in
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
                                    .init(address: address,
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
        )
    }
}

extension Network.Wallet.SubscriptionHub.Dependencies {
    static func storage(repository: Storage.Repository.Subscriptions) -> Self {
        StorageBackfillAdapter(repository: repository).makeDependencies()
    }
}
