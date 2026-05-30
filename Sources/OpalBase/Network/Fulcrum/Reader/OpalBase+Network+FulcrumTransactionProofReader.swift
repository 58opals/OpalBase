// OpalBase+Network+FulcrumTransactionProofReader.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    /// Reads transaction inclusion proofs from a Fulcrum server.
    ///
    /// This reader is an advanced adapter surface. Prefer `OpalBase.Wallet.Fulcrum`
    /// unless the application needs custom proof handling.
    public struct TransactionProofReader {
        private let client: any OpalBase.Network.Fulcrum.TransactionProofClient
        private let timeouts: OpalBase.Network.FulcrumRequestTimeout
        
        public init(
            client: OpalBase.Network.Fulcrum.Client,
            timeouts: OpalBase.Network.FulcrumRequestTimeout = .init()
        ) {
            self.init(client: client as any OpalBase.Network.Fulcrum.TransactionProofClient, timeouts: timeouts)
        }

        init(
            client: any OpalBase.Network.Fulcrum.TransactionProofClient,
            timeouts: OpalBase.Network.FulcrumRequestTimeout = .init()
        ) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func fetchMerkleProof(for transactionHash: OpalBase.Transaction.Hash) async throws -> OpalBase.Network.TransactionMerkleProof {
            let identifier = transactionHash.reverseOrder.hexadecimalString
            
            return try await OpalBase.Network.performWithFailureTranslation {
                let heightResult = try await client.fetchTransactionHeight(
                    transactionHash: identifier,
                    options: .init(timeout: timeouts.transactionMerkleProof)
                )
                guard let blockHeight = heightResult.height, blockHeight > 0 else {
                    throw OpalBase.Network.Error(
                        reason: .protocolViolation,
                        message: "Merkle proof requires a confirmed transaction height."
                    )
                }
                let result = try await client.fetchTransactionMerkleProof(
                    transactionHash: identifier,
                    blockHeight: blockHeight,
                    options: .init(timeout: timeouts.transactionMerkleProof)
                )
                guard result.blockHeight == blockHeight else {
                    throw OpalBase.Network.Error(
                        reason: .protocolViolation,
                        message: "Merkle proof block height mismatch: requested=\(blockHeight), response=\(result.blockHeight)"
                    )
                }
                try Self.validateMerkleProof(position: result.position, branch: result.merkle)
                
                return OpalBase.Network.TransactionMerkleProof(
                    blockHeight: result.blockHeight,
                    position: result.position,
                    merkle: result.merkle
                )
            }
        }
        
        public func fetchTransactionIdentifier(
            atHeight blockHeight: UInt,
            position: UInt,
            shouldIncludeMerkleProof: Bool
        ) async throws -> OpalBase.Network.TransactionPositionResolution {
            try await OpalBase.Network.performWithFailureTranslation {
                let result = try await client.fetchTransactionIdentifier(
                    blockHeight: blockHeight,
                    transactionPosition: position,
                    shouldIncludeMerkleProof: shouldIncludeMerkleProof,
                    options: .init(timeout: timeouts.transactionPositionResolution)
                )
                try Self.validateMerkleBranch(result.merkle)
                if shouldIncludeMerkleProof {
                    try Self.validateMerklePosition(position, branch: result.merkle)
                }
                _ = try OpalBase.Network.decodeTransactionHash(
                    from: result.transactionHash,
                    label: "position transaction identifier"
                )
                
                return OpalBase.Network.TransactionPositionResolution(
                    blockHeight: blockHeight,
                    transactionIdentifier: result.transactionHash,
                    merkle: result.merkle
                )
            }
        }
    }
}

private extension _OpalBase.Network.Fulcrum.TransactionProofReader {
    static func validateMerkleProof(position: UInt, branch: [String]) throws {
        try validateMerkleBranch(branch)
        try validateMerklePosition(position, branch: branch)
    }

    static func validateMerkleBranch(_ branch: [String]) throws {
        for (index, hashString) in branch.enumerated() {
            guard !hashString.hasPrefix("0x"), !hashString.hasPrefix("0X") else {
                throw SwiftFulcrum.Client.Error.client(
                    .protocolMismatch("Cannot decode merkle proof branch hash at index \(index).")
                )
            }
            
            let hashData: Data
            do {
                hashData = try Data(hexadecimalString: hashString)
            } catch {
                throw SwiftFulcrum.Client.Error.client(
                    .protocolMismatch("Cannot decode merkle proof branch hash at index \(index).")
                )
            }
            guard hashData.count == OpalBase.Transaction.Hash.expectedByteCount else {
                throw SwiftFulcrum.Client.Error.client(
                    .protocolMismatch(
                        "Merkle proof branch hash length at index \(index): expected \(OpalBase.Transaction.Hash.expectedByteCount) bytes, got \(hashData.count)"
                    )
                )
            }
        }
    }

    static func validateMerklePosition(_ position: UInt, branch: [String]) throws {
        guard branch.count < UInt.bitWidth else { return }
        let maximumPositionCount = UInt(1) << branch.count
        guard position < maximumPositionCount else {
            throw SwiftFulcrum.Client.Error.client(
                .protocolMismatch(
                    "Merkle proof position out of range for branch length: position=\(position), branchLength=\(branch.count)"
                )
            )
        }
    }
}
