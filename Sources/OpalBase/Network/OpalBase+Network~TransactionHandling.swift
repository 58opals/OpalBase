// OpalBase+Network~TransactionHandling.swift

import Foundation

extension _OpalBase.Network {
    typealias TransactionHandling = TransactionBroadcastClient & TransactionConfirmationClient
}

extension _OpalBase.Network {
    static func decodeTransactionHash(
        from identifier: String,
        label: String = "transaction identifier"
    ) throws -> OpalBase.Transaction.Hash {
        let data: Data
        do {
            data = try Data(hexadecimalString: identifier)
        } catch {
            throw OpalBase.Network.Error(reason: .decoding,
                                message: "Cannot decode \(label): \(identifier)")
        }
        
        guard data.count == OpalBase.Transaction.Hash.expectedByteCount else {
            throw OpalBase.Network.Error(
                reason: .decoding,
                message: "Invalid \(label) length: expected \(OpalBase.Transaction.Hash.expectedByteCount) bytes, got \(data.count)"
            )
        }
        
        return OpalBase.Transaction.Hash(dataFromRPC: data)
    }
}

extension _OpalBase.Network.TransactionBroadcastClient {
    func broadcast(transaction: OpalBase.Transaction) async throws -> OpalBase.Transaction.Hash {
        let rawHexadecimal = try transaction.encode().hexadecimalString
        let transactionIdentifier = try await broadcastTransaction(rawTransactionHexadecimal: rawHexadecimal)
        return try OpalBase.Network.decodeTransactionHash(from: transactionIdentifier)
    }
}

