// OpalBase+Network+TransactionConfirmationClient_.swift

import Foundation

extension _OpalBase.Network {
    public protocol TransactionConfirmationClient: Sendable {
        func fetchConfirmations(forTransactionIdentifier transactionIdentifier: String) async throws -> UInt?
        func fetchConfirmationStatus(for transactionHash: OpalBase.Transaction.Hash) async throws -> OpalBase.Network.TransactionConfirmationStatus
    }
}
