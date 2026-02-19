// Network+FulcrumClient+Subscription_.swift

import Foundation
import SwiftFulcrum

extension Network {
    protocol FulcrumSubscription: Sendable {
        var id: UUID { get }
        func prepareForReconnect() async
        func resubscribe(using fulcrum: SwiftFulcrum.FulcrumClient) async
        func cancel() async
        func fail(with error: Swift.Error) async
    }
}
