// TransactionMerkleProofValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Transaction.MerkleProof", .tags(.unit, .transaction))
struct TransactionMerkleProofValidator {
    @Test(
        "computeRoot rejects invalid proof shapes",
        arguments: InvalidMerkleProofShapeCase.allCases
    )
    fileprivate func computeRootRejectsInvalidProofShapes(_ proofShapeCase: InvalidMerkleProofShapeCase) {
        #expect(proofShapeCase.makeProof().computeRoot(for: proofShapeCase.transactionHash).isEmpty)
    }

    enum InvalidMerkleProofShapeCase: CaseIterable, CustomStringConvertible, Sendable {
        case transactionHashLength
        case branchHashLength
        case positionOutsideBranchDepth
        case unrepresentableBranchDepth

        var description: String {
            switch self {
            case .transactionHashLength:
                "transaction hash length"
            case .branchHashLength:
                "branch hash length"
            case .positionOutsideBranchDepth:
                "position outside branch depth"
            case .unrepresentableBranchDepth:
                "unrepresentable branch depth"
            }
        }

        var transactionHash: OpalBase.Transaction.Hash {
            switch self {
            case .transactionHashLength:
                OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 31))
            case .branchHashLength, .positionOutsideBranchDepth, .unrepresentableBranchDepth:
                OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32))
            }
        }

        func makeProof() -> OpalBase.Transaction.MerkleProof {
            switch self {
            case .transactionHashLength:
                OpalBase.Transaction.MerkleProof(
                    blockHeight: 10,
                    position: 0,
                    branch: [Data(repeating: 0x22, count: 32)]
                )
            case .branchHashLength:
                OpalBase.Transaction.MerkleProof(
                    blockHeight: 10,
                    position: 0,
                    branch: [Data(repeating: 0x22, count: 31)]
                )
            case .positionOutsideBranchDepth:
                OpalBase.Transaction.MerkleProof(
                    blockHeight: 10,
                    position: 2,
                    branch: [Data(repeating: 0x22, count: 32)]
                )
            case .unrepresentableBranchDepth:
                OpalBase.Transaction.MerkleProof(
                    blockHeight: 10,
                    position: 0,
                    branch: Array(repeating: Data(repeating: 0x22, count: 32), count: UInt32.bitWidth)
                )
            }
        }
    }
}
