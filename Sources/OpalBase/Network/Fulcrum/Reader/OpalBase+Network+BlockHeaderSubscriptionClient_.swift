// OpalBase+Network+BlockHeaderSubscriptionClient_.swift

import Foundation

extension _OpalBase.Network {
    public protocol BlockHeaderSubscriptionClient: Sendable {
        func subscribeToTip() async throws -> AsyncThrowingStream<OpalBase.Network.BlockHeaderSnapshot, any Swift.Error>
    }
}
