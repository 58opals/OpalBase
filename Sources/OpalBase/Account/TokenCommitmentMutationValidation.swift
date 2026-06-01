// TokenCommitmentMutationValidation.swift

import Foundation

enum TokenCommitmentMutationValidation {
    static func validateCommitment(_ commitment: Data) throws {
        try TokenOperationValidator.validateCommitmentLength(commitment) { maximum, actual in
            OpalBase.Account.Error.tokenMutationNonFungibleTokenCommitmentTooLong(
                maximum: maximum,
                actual: actual
            )
        }
    }

    static func validateDestination(_ destination: OpalBase.Address) throws {
        try TokenOperationValidator.requireTokenAwareAddress(destination) { offending in
            OpalBase.Account.Error.tokenMutationRequiresTokenAwareAddress(offending)
        }
    }
}
