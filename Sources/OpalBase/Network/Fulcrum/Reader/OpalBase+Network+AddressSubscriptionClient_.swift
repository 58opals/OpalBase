// OpalBase+Network+AddressSubscriptionClient_.swift

import Foundation

extension _OpalBase.Network {
    public protocol AddressSubscriptionClient: Sendable {
        func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, any Swift.Error>
    }
}
