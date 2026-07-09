// OpalBase+Network+TransactionHandling.swift

import Foundation

extension _OpalBase.Network {
    typealias TransactionHandling = TransactionBroadcastClient & TransactionConfirmationClient
}

extension _OpalBase.Network {
    static func decodeRawTransactionData(from rawTransactionHexadecimal: String) throws -> Data {
        guard !rawTransactionHexadecimal.hasPrefix("0x"),
              !rawTransactionHexadecimal.hasPrefix("0X") else {
            throw OpalBase.Network.Error(
                reason: .decoding,
                message: "Cannot decode raw transaction hex"
            )
        }

        do {
            return try Data(hexadecimalString: rawTransactionHexadecimal)
        } catch {
            throw OpalBase.Network.Error(
                reason: .decoding,
                message: "Cannot decode raw transaction hex"
            )
        }
    }

    static func decodeHashData(
        from hexadecimalString: String,
        label: String
    ) throws -> Data {
        guard !hexadecimalString.hasPrefix("0x"), !hexadecimalString.hasPrefix("0X") else {
            throw OpalBase.Network.Error(
                reason: .decoding,
                message: "Cannot decode \(label): \(hexadecimalString)"
            )
        }

        if let decodedByteCount = Data.unprefixedHexadecimalByteCount(hexadecimalString),
           decodedByteCount != OpalBase.Transaction.Hash.expectedByteCount {
            throw OpalBase.Network.Error(
                reason: .decoding,
                message: "Invalid \(label) length: expected \(OpalBase.Transaction.Hash.expectedByteCount) bytes, got \(decodedByteCount)"
            )
        }

        let data: Data
        do {
            data = try Data(hexadecimalString: hexadecimalString)
        } catch {
            throw OpalBase.Network.Error(
                reason: .decoding,
                message: "Cannot decode \(label): \(hexadecimalString)"
            )
        }

        guard data.count == OpalBase.Transaction.Hash.expectedByteCount else {
            throw OpalBase.Network.Error(
                reason: .decoding,
                message: "Invalid \(label) length: expected \(OpalBase.Transaction.Hash.expectedByteCount) bytes, got \(data.count)"
            )
        }

        return data
    }

    static func decodeTransactionHash(
        from identifier: String,
        label: String = "transaction identifier"
    ) throws -> OpalBase.Transaction.Hash {
        let data = try decodeHashData(from: identifier, label: label)
        return OpalBase.Transaction.Hash(dataFromRPC: data)
    }

    static func decodeBroadcastTransactionHash(
        from identifier: String,
        rawTransactionData: Data
    ) throws -> OpalBase.Transaction.Hash {
        let returnedHash = try decodeTransactionHash(
            from: identifier,
            label: "broadcast transaction identifier"
        )
        let expectedHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(rawTransactionData)
        )
        guard returnedHash == expectedHash else {
            throw OpalBase.Network.Error(
                reason: .protocolViolation,
                message: "Broadcast transaction hash mismatch",
                metadata: [
                    "expected": expectedHash.reverseOrder.hexadecimalString,
                    "actual": returnedHash.reverseOrder.hexadecimalString
                ]
            )
        }

        return returnedHash
    }
}

extension _OpalBase.Network.TransactionBroadcastClient {
    func broadcast(transaction: OpalBase.Transaction) async throws -> OpalBase.Transaction.Hash {
        let rawTransactionData = try transaction.encode()
        let rawHexadecimal = rawTransactionData.hexadecimalString
        let transactionIdentifier = try await broadcastTransaction(rawTransactionHexadecimal: rawHexadecimal)
        return try OpalBase.Network.decodeBroadcastTransactionHash(
            from: transactionIdentifier,
            rawTransactionData: rawTransactionData
        )
    }
}
