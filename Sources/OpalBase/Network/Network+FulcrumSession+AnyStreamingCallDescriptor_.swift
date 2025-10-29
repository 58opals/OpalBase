// Network+FulcrumSession+AnyStreamingCallDescriptor_.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
    protocol AnyStreamingCallDescriptor: Sendable {
        var identifier: UUID { get }
        var method: SwiftFulcrum.Method { get }
        
        func prepareForRestart() async
        func cancelAndFinish() async
        func finish(with error: Swift.Error) async
        func resubscribe(using session: Network.FulcrumSession, fulcrum: SwiftFulcrum.Fulcrum) async throws
    }
}
