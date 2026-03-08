// OpalBase+Account+TokenCommitmentMutation.swift

import Foundation

extension _OpalBase.Account {
    public struct TokenCommitmentMutation: Sendable {
        public enum Target: Sendable {
            case preferredInput(OpalBase.Transaction.Output.Unspent)
            case byGroup(OpalBase.Address.Book.TokenInventory.NonFungibleTokenGroup)
        }
        
        public let target: Target
        public let newCommitment: Data
        public let destination: OpalBase.Address
        public let bchAmount: OpalBase.Satoshi?
        public let shouldPreserveAttachedFungibleToWallet: Bool
        public let feeOverride: OpalBase.Wallet.FeePolicy.Override?
        public let feeContext: OpalBase.Wallet.FeePolicy.RecommendationContext
        public let shouldAllowDustDonation: Bool
        
        public init(target: Target,
                    newCommitment: Data,
                    destination: OpalBase.Address,
                    bchAmount: OpalBase.Satoshi? = nil,
                    shouldPreserveAttachedFungibleToWallet: Bool = true,
                    feeOverride: OpalBase.Wallet.FeePolicy.Override? = nil,
                    feeContext: OpalBase.Wallet.FeePolicy.RecommendationContext = .init(),
                    shouldAllowDustDonation: Bool = false) throws {
            try TokenCommitmentMutationValidationModel.validateCommitment(newCommitment)
            try TokenCommitmentMutationValidationModel.validateDestination(destination)
            self.target = target
            self.newCommitment = newCommitment
            self.destination = destination
            self.bchAmount = bchAmount
            self.shouldPreserveAttachedFungibleToWallet = shouldPreserveAttachedFungibleToWallet
            self.feeOverride = feeOverride
            self.feeContext = feeContext
            self.shouldAllowDustDonation = shouldAllowDustDonation
        }
    }
}

private enum TokenCommitmentMutationValidationModel {
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
