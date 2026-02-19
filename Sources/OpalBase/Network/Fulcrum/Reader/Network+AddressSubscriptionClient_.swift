// Network+AddressSubscriptionClient_.swift

import Foundation

extension Network {
    public protocol AddressSubscriptionClient: Sendable {
        func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<AddressSubscriptionUpdate, any Swift.Error>
    }
}
