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
    
    static func requireTokenAwareAddresses(
        _ addresses: [Address],
        makeError: (_ offending: [Address]) -> Swift.Error
    ) throws {
        let offending = addresses.filter { !$0.supportsTokens }
        guard offending.isEmpty else {
            throw makeError(offending)
        }
    }
    
    static func requireNonZeroFungibleAmount(
        _ amount: UInt64?,
        makeError: () -> Swift.Error
    ) throws {
        guard let amount else {
            return
        }
        guard amount > 0 else {
            throw makeError()
        }
    }
}
