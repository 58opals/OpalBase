// Network+FulcrumBlockHeaderReader.swift

import Foundation
import SwiftFulcrum

extension Network {
    public struct FulcrumBlockHeaderReader: BlockHeaderReadable {
        private let client: FulcrumClient
        private let timeouts: FulcrumRequestTimeout
        
        public init(client: FulcrumClient, timeouts: FulcrumRequestTimeout = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func fetchTip() async throws -> BlockHeaderSnapshot {
            try await Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.headers(.getTip)),
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.HeadersModel.GetTipModel.self,
                    options: .init(timeout: timeouts.headersTip)
                )
                return BlockHeaderSnapshot(height: result.height, headerHexadecimal: result.hex)
            }
        }
        
        public func subscribeToTip() async throws -> AsyncThrowingStream<BlockHeaderSnapshot, any Swift.Error> {
            try await Network.performWithFailureTranslation {
                let (initial, updates, cancel) = try await client.subscribe(
                    method: .blockchain(.headers(.subscribe)),
                    initialType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.HeadersModel.SubscribeModel.self,
                    notificationType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.HeadersModel.SubscribeNotificationModel.self,
                    options: .init(timeout: timeouts.headersSubscription)
                )
                
                return Network.makeSubscriptionStream(
                    initial: initial,
                    updates: updates,
                    cancel: cancel,
                    makeInitialUpdates: { snapshot in
                        [
                            BlockHeaderSnapshot(
                                height: snapshot.height,
                                headerHexadecimal: snapshot.hex
                            )
                        ]
                    },
                    makeUpdates: { notification in
                        notification.blocks.map { block in
                            BlockHeaderSnapshot(
                                height: block.height,
                                headerHexadecimal: block.hex
                            )
                        }
                    },
                    deduplicationKey: { snapshot in
                        snapshot
                    }
                )
            }
        }
    }
}
