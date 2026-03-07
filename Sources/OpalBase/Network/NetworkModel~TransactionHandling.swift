// NetworkModel~TransactionHandling.swift

import Foundation

extension NetworkModel {
    public typealias TransactionHandling = TransactionBroadcastClient & TransactionConfirmationClient
}

extension NetworkModel {
    static func decodeTransactionHash(
        from identifier: String,
        label: String = "transaction identifier"
    ) throws -> TransactionModel.HashModel {
        let data: Data
        do {
            data = try Data(hexadecimalString: identifier)
        } catch {
            throw NetworkModel.Error(reason: .decoding,
                                message: "Cannot decode \(label): \(identifier)")
        }
        
        guard data.count == TransactionModel.HashModel.expectedByteCount else {
            throw NetworkModel.Error(
                reason: .decoding,
                message: "Invalid \(label) length: expected \(TransactionModel.HashModel.expectedByteCount) bytes, got \(data.count)"
            )
        }
        
        return TransactionModel.HashModel(dataFromRPC: data)
    }
}

extension NetworkModel.TransactionBroadcastClient {
    func broadcast(transaction: TransactionModel) async throws -> TransactionModel.HashModel {
        let rawHexadecimal = try transaction.encode().hexadecimalString
        let transactionIdentifier = try await broadcastTransaction(rawTransactionHexadecimal: rawHexadecimal)
        return try NetworkModel.decodeTransactionHash(from: transactionIdentifier)
    }
}

