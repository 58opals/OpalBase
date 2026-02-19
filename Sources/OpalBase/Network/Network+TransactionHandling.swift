// Network+TransactionHandling.swift

import Foundation

extension Network {
    public typealias TransactionHandling = TransactionBroadcastClient & TransactionConfirmationClient
}

extension Network {
    static func decodeTransactionHash(
        from identifier: String,
        label: String = "transaction identifier"
    ) throws -> Transaction.Hash {
        do {
            let data = try Data(hexadecimalString: identifier)
            return Transaction.Hash(dataFromRPC: data)
        } catch {
            throw Network.Error(reason: .decoding,
                                message: "Cannot decode \(label): \(identifier)")
        }
    }
}

extension Network.TransactionBroadcastClient {
    func broadcast(transaction: Transaction) async throws -> Transaction.Hash {
        let rawHexadecimal = try transaction.encode().hexadecimalString
        let transactionIdentifier = try await broadcastTransaction(rawTransactionHexadecimal: rawHexadecimal)
        return try Network.decodeTransactionHash(from: transactionIdentifier)
    }
}
