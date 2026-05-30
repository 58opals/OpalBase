// OpalBase+Network+BlockHeaderSubscriptionClient.swift

import Foundation

extension _OpalBase.Network {
    protocol BlockHeaderSubscriptionClient: Sendable {
        func subscribeToTip() async throws -> AsyncThrowingStream<OpalBase.Network.BlockHeaderSnapshot, any Swift.Error>
    }
}
