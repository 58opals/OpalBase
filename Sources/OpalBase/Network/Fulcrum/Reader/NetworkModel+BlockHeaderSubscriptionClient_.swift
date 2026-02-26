// NetworkModel+BlockHeaderSubscriptionClient_.swift

import Foundation

extension NetworkModel {
    public protocol BlockHeaderSubscriptionClient: Sendable {
        func subscribeToTip() async throws -> AsyncThrowingStream<BlockHeaderSnapshotModel, any Swift.Error>
    }
}
