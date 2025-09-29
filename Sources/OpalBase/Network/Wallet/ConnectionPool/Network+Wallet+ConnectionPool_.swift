// Network+Wallet+ConnectionPool_.swift

import Foundation

extension Network.Wallet {
    public protocol ConnectionPool: Sendable {
        var currentStatus: Network.Wallet.Status { get async }
        
        func observeStatus() async -> AsyncStream<Network.Wallet.Status>
        func acquireGateway() async throws -> Network.Gateway
        func acquireNode() async throws -> Network.Wallet.Node
        func reportFailure() async throws
    }
}
