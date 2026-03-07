// NetworkModel+FulcrumSubscriptionClient_.swift

import Foundation
import SwiftFulcrum

extension NetworkModel {
    protocol FulcrumSubscriptionClient: Sendable {
        var id: UUID { get }
        func prepareForReconnect() async
        func resubscribe(using fulcrum: SwiftFulcrum.Client) async
        func cancel() async
        func fail(with error: Swift.Error) async
    }
}

