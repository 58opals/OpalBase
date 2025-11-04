// Network+FulcrumBlockHeaderReader.swift

import Foundation
import SwiftFulcrum

extension Network {
    public struct FulcrumBlockHeaderReader: BlockHeaderReadable {
        private let client: FulcrumClient
        private let timeouts: FulcrumServiceTimeouts

        public init(client: FulcrumClient, timeouts: FulcrumServiceTimeouts = .init()) {
            self.client = client
            self.timeouts = timeouts
        }

        public func fetchTip() async throws -> BlockHeaderSnapshot {
            do {
                let result = try await client.request(
                    method: .blockchain(.headers(.getTip)),
                    responseType: Response.Result.Blockchain.Headers.GetTip.self,
                    options: .init(timeout: timeouts.headersTip)
                )
                return BlockHeaderSnapshot(height: result.height, headerHexadecimal: result.hex)
            } catch {
                throw NetworkFulcrumErrorTranslator.translate(error)
            }
        }

        public func subscribeToTip() async throws -> AsyncThrowingStream<BlockHeaderSnapshot, Network.Failure> {
            do {
                let (initial, updates, cancel) = try await client.subscribe(
                    method: .blockchain(.headers(.subscribe)),
                    initialType: Response.Result.Blockchain.Headers.Subscribe.self,
                    notificationType: Response.Result.Blockchain.Headers.SubscribeNotification.self,
                    options: .init(timeout: timeouts.headersSubscription)
                )

                return AsyncThrowingStream { continuation in
                    let initialSnapshot = BlockHeaderSnapshot(height: initial.height, headerHexadecimal: initial.hex)
                    continuation.yield(initialSnapshot)

                    let task = Task {
                        do {
                            for try await notification in updates {
                                for block in notification.blocks {
                                    let snapshot = BlockHeaderSnapshot(height: block.height, headerHexadecimal: block.hex)
                                    continuation.yield(snapshot)
                                }
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: NetworkFulcrumErrorTranslator.translate(error))
                        }
                    }

                    continuation.onTermination = { _ in
                        task.cancel()
                        Task { await cancel() }
                    }
                }
            } catch {
                throw NetworkFulcrumErrorTranslator.translate(error)
            }
        }
    }
}
