// NetworkModel+TransactionConfirmationClient_.swift

import Foundation

extension NetworkModel {
    public protocol TransactionConfirmationClient: Sendable {
        func fetchConfirmations(forTransactionIdentifier transactionIdentifier: String) async throws -> UInt?
        func fetchConfirmationStatus(for transactionHash: TransactionModel.HashModel) async throws -> NetworkModel.TransactionConfirmationStatusModel
    }
}
