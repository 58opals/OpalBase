// Network+TransactionReadable_.swift

import Foundation

extension Network {
    public protocol TransactionReadable: Sendable {
        func fetchRawTransaction(for transactionHash: Transaction.Hash) async throws -> Data
    }
}
