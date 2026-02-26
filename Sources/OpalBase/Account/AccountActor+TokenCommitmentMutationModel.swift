// AccountActor+TokenCommitmentMutationModel.swift

import Foundation

extension AccountActor {
    public struct TokenCommitmentMutationModel: Sendable {
        public enum Target: Sendable {
            case preferredInput(TransactionModel.OutputModel.UnspentModel)
            case byGroup(AddressModel.BookActor.TokenInventoryModel.NonFungibleTokenGroup)
        }
        
        public let target: Target
        public let newCommitment: Data
        public let destination: AddressModel
        public let bchAmount: SatoshiModel?
        public let shouldPreserveAttachedFungibleToWallet: Bool
        public let feeOverride: WalletActor.FeePolicy.Override?
        public let feeContext: WalletActor.FeePolicy.RecommendationContext
        public let shouldAllowDustDonation: Bool
        
        public init(target: Target,
                    newCommitment: Data,
                    destination: AddressModel,
                    bchAmount: SatoshiModel? = nil,
                    shouldPreserveAttachedFungibleToWallet: Bool = true,
                    feeOverride: WalletActor.FeePolicy.Override? = nil,
                    feeContext: WalletActor.FeePolicy.RecommendationContext = .init(),
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
            AccountActor.Error.tokenMutationNonFungibleTokenCommitmentTooLong(
                maximum: maximum,
                actual: actual
            )
        }
    }
    
    static func validateDestination(_ destination: AddressModel) throws {
        try TokenOperationValidator.requireTokenAwareAddress(destination) { offending in
            AccountActor.Error.tokenMutationRequiresTokenAwareAddress(offending)
        }
    }
}
