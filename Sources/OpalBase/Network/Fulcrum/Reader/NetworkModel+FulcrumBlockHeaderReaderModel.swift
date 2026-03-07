// NetworkModel+FulcrumBlockHeaderReaderModel.swift

import Foundation
import SwiftFulcrum

extension NetworkModel {
    public struct FulcrumBlockHeaderReaderModel: BlockHeaderReadable {
        private let client: FulcrumClient
        private let timeouts: FulcrumRequestTimeoutModel
        
        public init(client: FulcrumClient, timeouts: FulcrumRequestTimeoutModel = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func fetchTip() async throws -> BlockHeaderSnapshotModel {
            try await NetworkModel.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.headers(.getTip)),
                    responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Headers.GetTip.self,
                    options: .init(timeout: timeouts.headersTip)
                )
                return BlockHeaderSnapshotModel(height: result.height, headerHexadecimal: result.hex)
            }
        }
        
        public func subscribeToTip() async throws -> AsyncThrowingStream<BlockHeaderSnapshotModel, any Swift.Error> {
            try await NetworkModel.performWithFailureTranslation {
                let (initial, updates, cancel) = try await client.subscribe(
                    method: .blockchain(.headers(.subscribe)),
                    initialType: SwiftFulcrum.RPC.Response.Result.Blockchain.Headers.Subscribe.self,
                    notificationType: SwiftFulcrum.RPC.Response.Result.Blockchain.Headers.SubscribeNotification.self,
                    options: .init(timeout: timeouts.headersSubscription)
                )
                
                return NetworkModel.makeSubscriptionStream(
                    initial: initial,
                    updates: updates,
                    cancel: cancel,
                    makeInitialUpdates: { snapshot in
                        [
                            BlockHeaderSnapshotModel(
                                height: snapshot.height,
                                headerHexadecimal: snapshot.hex
                            )
                        ]
                    },
                    makeUpdates: { notification in
                        notification.blocks.map { block in
                            BlockHeaderSnapshotModel(
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
