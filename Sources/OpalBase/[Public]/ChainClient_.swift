// ChainClient_.swift

import Foundation

public protocol ChainClient: Sendable {
    func connect() async throws
    func disconnect()
}
