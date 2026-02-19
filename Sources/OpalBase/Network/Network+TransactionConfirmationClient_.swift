// Network+TransactionConfirmationClient_.swift

import Foundation

extension Network {
    public protocol TransactionConfirmationClient: Sendable {
        func fetchConfirmations(forTransactionIdentifier transactionIdentifier: String) async throws -> UInt?
        func fetchConfirmationStatus(for transactionHash: Transaction.Hash) async throws -> Network.TransactionConfirmationStatus
    }
}
