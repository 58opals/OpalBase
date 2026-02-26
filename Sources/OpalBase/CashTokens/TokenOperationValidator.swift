// TokenOperationValidator.swift

import Foundation

enum TokenOperationValidator {
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
        _ address: AddressModel,
        makeError: (_ offending: [AddressModel]) -> Swift.Error
    ) throws {
        guard address.isTokenAware else {
            throw makeError([address])
        }
    }
    
    static func requireTokenAwareAddresses(
        _ addresses: [AddressModel],
        makeError: (_ offending: [AddressModel]) -> Swift.Error
    ) throws {
        let offending = addresses.filter { !$0.isTokenAware }
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
