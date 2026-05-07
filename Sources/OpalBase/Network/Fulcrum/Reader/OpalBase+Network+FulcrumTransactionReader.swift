// OpalBase+Network+FulcrumTransactionReader.swift

import Foundation

extension _OpalBase.Network.Fulcrum {
    /// Reads transaction data from a Fulcrum server.
    ///
    /// Most wallet applications should use `OpalBase.Wallet.Fulcrum` for live
    /// synchronization. Use this reader directly when composing a custom network
    /// adapter.
    public struct TransactionReader {
        private let client: any OpalBase.Network.Fulcrum.TransactionReaderClient
        private let timeouts: OpalBase.Network.FulcrumRequestTimeout
        private let cache: OpalBase.Transaction.Cache
        
        public init(
            client: OpalBase.Network.Fulcrum.Client,
            timeouts: OpalBase.Network.FulcrumRequestTimeout = .init(),
            cache: OpalBase.Transaction.Cache = .init()
        ) {
            self.init(
                client: client as any OpalBase.Network.Fulcrum.TransactionReaderClient,
                timeouts: timeouts,
                cache: cache
            )
        }

        init(
            client: any OpalBase.Network.Fulcrum.TransactionReaderClient,
            timeouts: OpalBase.Network.FulcrumRequestTimeout = .init(),
            cache: OpalBase.Transaction.Cache = .init()
        ) {
            self.client = client
            self.timeouts = timeouts
            self.cache = cache
        }
        
        public func fetchDetailedTransaction(forTransactionIdentifier transactionIdentifier: String) async throws -> OpalBase.Transaction.Detail {
            let hash = try OpalBase.Network.decodeTransactionHash(from: transactionIdentifier)
            return try await fetchDetailedTransaction(for: hash)
        }
        
        private func makeDetailed(
            transactionHash: OpalBase.Transaction.Hash,
            rawTransactionData: Data,
            isVerbose: TransactionGetVerbose?
        ) throws -> OpalBase.Transaction.Detail {
            try validatePayloadHash(rawTransactionData, expected: transactionHash)
            let (transaction, bytesRead) = try OpalBase.Transaction.decode(from: rawTransactionData)
            guard bytesRead == rawTransactionData.count else {
                throw OpalBase.Network.Error(
                    reason: .decoding,
                    message: "Transaction payload has trailing bytes"
                )
            }
            let blockHash = try decodeBlockHash(isVerbose?.blockhash)
            
            return OpalBase.Transaction.Detail(
                transaction: transaction,
                blockHash: blockHash,
                blockTime: isVerbose?.blocktime,
                confirmations: isVerbose?.confirmations,
                hash: transactionHash,
                rawTransactionData: rawTransactionData,
                size: isVerbose?.size ?? UInt32(rawTransactionData.count),
                time: isVerbose?.time
            )
        }

        private func decodeBlockHash(_ hexadecimalString: String?) throws -> Data? {
            guard let hexadecimalString else { return nil }
            let blockHash = try Data(hexadecimalString: hexadecimalString)
            guard blockHash.count == OpalBase.Transaction.Hash.expectedByteCount else {
                throw OpalBase.Network.Error(
                    reason: .decoding,
                    message: "Invalid block hash length: expected \(OpalBase.Transaction.Hash.expectedByteCount) bytes, got \(blockHash.count)"
                )
            }
            return blockHash
        }

        private func validatePayloadHash(
            _ rawTransactionData: Data,
            expected transactionHash: OpalBase.Transaction.Hash
        ) throws {
            let actualHash = OpalBase.Transaction.Hash(
                naturalOrder: OpalCryptoAdapter.hash256(rawTransactionData)
            )
            guard actualHash == transactionHash else {
                throw OpalBase.Network.Error(
                    reason: .protocolViolation,
                    message: "Transaction payload hash mismatch",
                    metadata: [
                        "expected": transactionHash.reverseOrder.hexadecimalString,
                        "actual": actualHash.reverseOrder.hexadecimalString
                    ]
                )
            }
        }
        
        public func fetchDetailedTransaction(for transactionHash: OpalBase.Transaction.Hash) async throws -> OpalBase.Transaction.Detail {
            if let cached = await cache.loadTransaction(at: transactionHash) {
                return cached
            }
            
            do {
                let detailed = try await fetchDetailedTransactionUsingVerboseResponse(for: transactionHash)
                await cache.put(detailed, at: transactionHash)
                return detailed
            } catch let failure as OpalBase.Network.Error where failure.reason == .decoding {
                let detailed = try await fetchDetailedTransactionUsingRawResponse(for: transactionHash)
                await cache.put(detailed, at: transactionHash)
                return detailed
            } catch let failure as OpalBase.Network.Error {
                throw failure
            }
        }
        
        public func fetchRawTransaction(for transactionHash: OpalBase.Transaction.Hash) async throws -> Data {
            if let cached = await cache.loadTransaction(at: transactionHash) {
                return cached.rawTransactionData
            }
            
            let identifier = transactionHash.reverseOrder.hexadecimalString
            
            return try await OpalBase.Network.performWithFailureTranslation {
                let rawTransactionHex = try await client.fetchRawTransaction(
                    transactionHash: identifier,
                    options: .init(timeout: timeouts.transactionConfirmations)
                )
                
                let rawTransactionData = try Data(hexadecimalString: rawTransactionHex)
                try validatePayloadHash(rawTransactionData, expected: transactionHash)
                let (_, bytesRead) = try OpalBase.Transaction.decode(from: rawTransactionData)
                guard bytesRead == rawTransactionData.count else {
                    throw OpalBase.Network.Error(
                        reason: .decoding,
                        message: "Transaction payload has trailing bytes"
                    )
                }
                return rawTransactionData
            }
        }
        
        private func fetchVerboseTransaction(for transactionHash: OpalBase.Transaction.Hash) async throws -> TransactionGetVerbose {
            let identifier = transactionHash.reverseOrder.hexadecimalString
            
            return try await OpalBase.Network.performWithFailureTranslation {
                let result = try await client.fetchVerboseTransaction(
                    transactionHash: identifier,
                    options: .init(timeout: timeouts.transactionConfirmations)
                )
                guard let size = UInt32(exactly: result.size) else {
                    throw OpalBase.Network.Error(
                        reason: .decoding,
                        message: "Invalid transaction size: \(result.size)"
                    )
                }
                guard result.hash.caseInsensitiveCompare(identifier) == .orderedSame,
                      result.transactionID.caseInsensitiveCompare(identifier) == .orderedSame else {
                    throw OpalBase.Network.Error(
                        reason: .protocolViolation,
                        message: "Verbose transaction identifier mismatch",
                        metadata: [
                            "expected": identifier,
                            "hash": result.hash,
                            "txid": result.transactionID
                        ]
                    )
                }
                return .init(hex: result.hex,
                             blockhash: result.blockHash,
                             hash: result.hash,
                             blocktime: try Self.makeOptionalUInt32(result.blocktime, fieldName: "blocktime"),
                             confirmations: try Self.makeOptionalUInt32(result.confirmations, fieldName: "confirmations"),
                             size: size,
                             time: try Self.makeOptionalUInt32(result.time, fieldName: "time"),
                             transactionID: result.transactionID)
            }
        }

        private static func makeOptionalUInt32(
            _ value: UInt?,
            fieldName: String
        ) throws -> UInt32? {
            guard let value else { return nil }
            guard let converted = UInt32(exactly: value) else {
                throw OpalBase.Network.Error(
                    reason: .decoding,
                    message: "Invalid transaction \(fieldName): \(value)"
                )
            }
            return converted
        }

        private func fetchDetailedTransactionUsingVerboseResponse(
            for transactionHash: OpalBase.Transaction.Hash
        ) async throws -> OpalBase.Transaction.Detail {
            try await OpalBase.Network.performWithFailureTranslation {
                let verbose = try await fetchVerboseTransaction(for: transactionHash)
                let rawTransactionData = try Data(hexadecimalString: verbose.hex)
                return try makeDetailed(
                    transactionHash: transactionHash,
                    rawTransactionData: rawTransactionData,
                    isVerbose: verbose
                )
            }
        }

        private func fetchDetailedTransactionUsingRawResponse(
            for transactionHash: OpalBase.Transaction.Hash
        ) async throws -> OpalBase.Transaction.Detail {
            try await OpalBase.Network.performWithFailureTranslation {
                let rawTransactionData = try await fetchRawTransaction(for: transactionHash)
                return try makeDetailed(
                    transactionHash: transactionHash,
                    rawTransactionData: rawTransactionData,
                    isVerbose: nil
                )
            }
        }
        
        private struct TransactionGetVerbose: Codable, Sendable {
            let hex: String
            let blockhash: String?
            let hash: String
            let blocktime: UInt32?
            let confirmations: UInt32?
            let size: UInt32?
            let time: UInt32?
            let transactionID: String
        }
    }
}

extension _OpalBase.Network.Fulcrum.TransactionReader: Sendable {}
extension _OpalBase.Network.Fulcrum.TransactionReader: OpalBase.Network.TransactionReadableClient {}
