// NetworkModel+TransactionReadableClient_.swift

import Foundation

extension NetworkModel {
    public protocol TransactionReadableClient: Sendable {
        func fetchRawTransaction(for transactionHash: TransactionModel.HashModel) async throws -> Data
    }
}

