// OpalBase+Network~TransactionHandling.swift

import Foundation

extension _OpalBase.Network {
    public typealias TransactionHandling = TransactionBroadcastClient & TransactionConfirmationClient
}

extension _OpalBase.Network {
    static func decodeTransactionHash(
        from identifier: String,
        label: String = "transaction identifier"
    ) throws -> OpalBase.Transaction.HashModel {
        let data: Data
        do {
            data = try Data(hexadecimalString: identifier)
        } catch {
            throw OpalBase.Network.Error(reason: .decoding,
                                message: "Cannot decode \(label): \(identifier)")
        }
        
        guard data.count == OpalBase.Transaction.HashModel.expectedByteCount else {
            throw OpalBase.Network.Error(
                reason: .decoding,
                message: "Invalid \(label) length: expected \(OpalBase.Transaction.HashModel.expectedByteCount) bytes, got \(data.count)"
            )
        }
        
        return OpalBase.Transaction.HashModel(dataFromRPC: data)
    }
}

extension _OpalBase.Network.TransactionBroadcastClient {
    func broadcast(transaction: OpalBase.Transaction) async throws -> OpalBase.Transaction.HashModel {
        let rawHexadecimal = try transaction.encode().hexadecimalString
        let transactionIdentifier = try await broadcastTransaction(rawTransactionHexadecimal: rawHexadecimal)
        return try OpalBase.Network.decodeTransactionHash(from: transactionIdentifier)
    }
}

