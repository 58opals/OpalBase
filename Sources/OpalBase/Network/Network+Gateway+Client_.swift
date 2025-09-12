// Network+Gateway+Client_.swift

import Foundation

extension Network.Gateway {
    public protocol Client: Sendable {
        func currentMempool() async throws -> Set<Transaction.Hash>
        func broadcast(_ transaction: Transaction) async throws
        func fetch(_ hash: Transaction.Hash) async throws -> Transaction?
    }
}
