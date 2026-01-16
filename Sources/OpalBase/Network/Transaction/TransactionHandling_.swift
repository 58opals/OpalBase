// Network+TransactionHandling_.swift

import Foundation

extension Network {
    public typealias TransactionHandling = TransactionBroadcasting & TransactionConfirming
    
    public protocol TransactionBroadcasting: Sendable {
        func broadcastTransaction(rawTransactionHexadecimal: String) async throws -> String
    }
    
    public protocol TransactionConfirming: Sendable {
        func fetchConfirmations(forTransactionIdentifier transactionIdentifier: String) async throws -> UInt?
        func fetchConfirmationStatus(for transactionHash: Transaction.Hash) async throws -> Network.TransactionConfirmationStatus
    }
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
            throw Network.Failure(reason: .decoding,
                                  message: "Cannot decode \(label): \(identifier)")
        }
    }
}

extension Network.TransactionBroadcasting {
    func broadcast(transaction: Transaction) async throws -> Transaction.Hash {
        let rawHexadecimal = transaction.encode().hexadecimalString
        let transactionIdentifier = try await broadcastTransaction(rawTransactionHexadecimal: rawHexadecimal)
        return try Network.decodeTransactionHash(from: transactionIdentifier)
    }
}
