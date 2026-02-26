// NetworkModel+AddressSubscriptionClient_.swift

import Foundation

extension NetworkModel {
    public protocol AddressSubscriptionClient: Sendable {
        func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<AddressSubscriptionUpdateModel, any Swift.Error>
    }
}
