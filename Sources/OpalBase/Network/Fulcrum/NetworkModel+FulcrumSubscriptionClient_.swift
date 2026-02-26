// NetworkModel+FulcrumClient+Subscription_.swift

import Foundation
import SwiftFulcrum

extension NetworkModel {
    protocol FulcrumSubscriptionClient: Sendable {
        var id: UUID { get }
        func prepareForReconnect() async
        func resubscribe(using fulcrum: SwiftFulcrum.FulcrumClient) async
        func cancel() async
        func fail(with error: Swift.Error) async
    }
}
