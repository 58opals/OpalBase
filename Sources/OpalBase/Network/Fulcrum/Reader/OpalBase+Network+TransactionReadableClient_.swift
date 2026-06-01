// OpalBase+Network+TransactionReadableClient_.swift

import Foundation

extension _OpalBase.Network {
    protocol TransactionReadableClient: Sendable {
        func fetchRawTransaction(for transactionHash: OpalBase.Transaction.Hash) async throws -> Data
    }
}
