// Account+Monitor~SwiftFulcrum.swift

import Foundation
import SwiftFulcrum

extension Account.Monitor {
    public func start(for addresses: [Address], using fulcrum: Fulcrum) async throws -> AsyncThrowingStream<Void, Swift.Error> {
        var streams: [AsyncThrowingStream<Response.Result.Blockchain.Address.SubscribeNotification, Swift.Error>] = .init()
        
        for address in addresses {
            let (_, _, _, stream, cancel) = try await address.subscribe(fulcrum: fulcrum)
            
            await storeCancel(cancel)
            streams.append(stream)
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
