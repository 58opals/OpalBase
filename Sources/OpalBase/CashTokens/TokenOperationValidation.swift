// TokenOperationValidation.swift

import Foundation

enum TokenOperationValidation {
    static let maximumCommitmentByteCount = 40
    
    static func validateCommitmentLength(
        _ commitment: Data,
        makeError: (_ maximum: Int, _ actual: Int) -> Swift.Error
    ) throws {
        guard commitment.count <= maximumCommitmentByteCount else {
            throw makeError(maximumCommitmentByteCount, commitment.count)
        }
    }
    
    static func requireTokenAwareAddress(
        _ address: Address,
        makeError: (_ offending: [Address]) -> Swift.Error
    ) throws {
        guard address.supportsTokens else {
            throw makeError([address])
        }
    }
}
