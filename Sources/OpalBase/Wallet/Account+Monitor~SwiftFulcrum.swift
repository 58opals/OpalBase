// Account+Monitor~SwiftFulcrum.swift

import Foundation
import SwiftFulcrum

extension Account.Monitor {
    public func start(for addresses: [Address], using fulcrum: Fulcrum) async throws -> AsyncThrowingStream<Void, Swift.Error> {
        guard !addresses.isEmpty else { throw Account.Monitor.Error.emptyAddresses }
        try beginMonitoring()
        
        let streams = try await withThrowingTaskGroup(of: AsyncThrowingStream<Response.Result.Blockchain.Address.SubscribeNotification, Swift.Error>.self) { group in
            for address in addresses {
                group.addTask {
                    let (_, _, _, stream, cancel) = try await address.subscribe(fulcrum: fulcrum)
                    await self.storeCancel(cancel)
                    return stream
                }
            }
            
            var collected: [AsyncThrowingStream<Response.Result.Blockchain.Address.SubscribeNotification, Swift.Error>] = []
            for try await stream in group { collected.append(stream) }
            return collected
        }
        
        return AsyncThrowingStream { continuation in
            for stream in streams {
                Task {
                    do {
                        for try await _ in stream {
                            continuation.yield(())
                        }
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
            
            continuation.onTermination = { _ in
                Task { await self.stop() }
            }
        }
    }
}
