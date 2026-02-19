// Network+BlockHeaderSubscriptionClient_.swift

import Foundation

extension Network {
    public protocol BlockHeaderSubscriptionClient: Sendable {
        func subscribeToTip() async throws -> AsyncThrowingStream<BlockHeaderSnapshot, any Swift.Error>
    }
}
