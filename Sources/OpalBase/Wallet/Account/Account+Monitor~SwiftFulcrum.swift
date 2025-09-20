// Account+Monitor~SwiftFulcrum.swift

import Foundation
import SwiftFulcrum

extension Account.Monitor {
    public func start(for addresses: [Address],
                      using fulcrum: Fulcrum,
                      through hub: Network.Wallet.SubscriptionHub) async throws -> (stream: AsyncThrowingStream<Void, Swift.Error>, consumerID: UUID) {
        guard !addresses.isEmpty else { throw Account.Monitor.Error.emptyAddresses }
        
        let consumerID = UUID()
        do {
            try beginMonitoring(consumerID: consumerID)
            let handle = try await hub.makeStream(for: addresses, using: fulcrum, consumerID: consumerID)
            
            let stream = AsyncThrowingStream<Void, Swift.Error>(bufferingPolicy: .bufferingNewest(1)) { continuation in
                let task = Task { [weak self] in
                    guard let self else { return }
                    do {
                        for try await _ in handle.notifications {
                            await self.scheduleCoalescedEmit { continuation.yield(()) }
                        }
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in
                    task.cancel()
                    Task { [weak self] in
                        guard let self else { return }
                        await self.stop(hub: hub)
                    }
                }
            }
            
            return (stream, handle.id)
        } catch let error as Account.Monitor.Error {
            await stop(hub: hub)
            throw error
        } catch {
            await stop(hub: hub)
            throw Account.Monitor.Error.monitoringFailed(error)
        }
    }
}
