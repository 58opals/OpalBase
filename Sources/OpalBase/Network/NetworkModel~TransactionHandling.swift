// NetworkModel+TransactionHandling.swift

import Foundation

extension NetworkModel {
    public typealias TransactionHandling = TransactionBroadcastClient & TransactionConfirmationClient
}

extension NetworkModel {
    static func decodeTransactionHash(
        from identifier: String,
        label: String = "transaction identifier"
    ) throws -> TransactionModel.HashModel {
        do {
            let data = try Data(hexadecimalString: identifier)
            return TransactionModel.HashModel(dataFromRPC: data)
        } catch {
            throw NetworkModel.Error(reason: .decoding,
                                message: "Cannot decode \(label): \(identifier)")
        }
    }
}

extension NetworkModel.TransactionBroadcastClient {
    func broadcast(transaction: TransactionModel) async throws -> TransactionModel.HashModel {
        let rawHexadecimal = try transaction.encode().hexadecimalString
        let transactionIdentifier = try await broadcastTransaction(rawTransactionHexadecimal: rawHexadecimal)
        return try NetworkModel.decodeTransactionHash(from: transactionIdentifier)
    }
}
