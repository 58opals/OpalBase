// OpalBase+Network+FulcrumTransactionReader.swift

import Foundation

extension _OpalBase.Network {
    public struct FulcrumTransactionReader {
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
            let (transaction, _) = try OpalBase.Transaction.decode(from: rawTransactionData)
            let blockHash = isVerbose?.blockhash.flatMap { try? Data(hexadecimalString: $0) }
            
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
                
                return try Data(hexadecimalString: rawTransactionHex)
            }
        }
        
        private func fetchVerboseTransaction(for transactionHash: OpalBase.Transaction.Hash) async throws -> TransactionGetVerbose {
            let identifier = transactionHash.reverseOrder.hexadecimalString
            
            return try await OpalBase.Network.performWithFailureTranslation {
                let result = try await client.fetchVerboseTransaction(
                    transactionHash: identifier,
                    options: .init(timeout: timeouts.transactionConfirmations)
                )
                return .init(hex: result.hex,
                             blockhash: result.blockHash,
                             blocktime: result.blocktime.flatMap(UInt32.init(exactly:)),
                             confirmations: result.confirmations.flatMap(UInt32.init(exactly:)),
                             size: UInt32(result.size),
                             time: result.time.flatMap(UInt32.init(exactly:)))
            }
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
            let blocktime: UInt32?
            let confirmations: UInt32?
            let size: UInt32?
            let time: UInt32?
        }
    }
}

extension _OpalBase.Network.FulcrumTransactionReader: Sendable {}
extension _OpalBase.Network.FulcrumTransactionReader: OpalBase.Network.TransactionReadableClient {}
