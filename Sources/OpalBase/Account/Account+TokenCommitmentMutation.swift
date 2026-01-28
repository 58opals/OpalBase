// Account+TokenCommitmentMutation.swift

import Foundation

extension Account {
    public struct TokenCommitmentMutation: Sendable {
        public enum Target: Sendable {
            case preferredInput(Transaction.Output.Unspent)
            case byGroup(Address.Book.TokenInventory.NonFungibleTokenGroup)
        }
        
        public let target: Target
        public let newCommitment: Data
        public let destination: Address
        public let bchAmount: Satoshi?
        public let preserveAttachedFungibleToWallet: Bool
        public let feeOverride: Wallet.FeePolicy.Override?
        public let feeContext: Wallet.FeePolicy.RecommendationContext
        public let shouldAllowDustDonation: Bool
        
        public init(target: Target,
                    newCommitment: Data,
                    destination: Address,
                    bchAmount: Satoshi? = nil,
                    preserveAttachedFungibleToWallet: Bool = true,
                    feeOverride: Wallet.FeePolicy.Override? = nil,
                    feeContext: Wallet.FeePolicy.RecommendationContext = .init(),
                    shouldAllowDustDonation: Bool = false) throws {
            try TokenCommitmentMutationValidation.validateCommitment(newCommitment)
            try TokenCommitmentMutationValidation.validateDestination(destination)
            self.target = target
            self.newCommitment = newCommitment
            self.destination = destination
            self.bchAmount = bchAmount
            self.preserveAttachedFungibleToWallet = preserveAttachedFungibleToWallet
            self.feeOverride = feeOverride
            self.feeContext = feeContext
            self.shouldAllowDustDonation = shouldAllowDustDonation
        }
    }
}

private enum TokenCommitmentMutationValidation {
    static func validateCommitment(_ commitment: Data) throws {
        let maximumCommitmentByteCount = TokenOperationValidation.maximumCommitmentByteCount
        guard commitment.count <= maximumCommitmentByteCount else {
            throw Account.Error.tokenMutationNonFungibleTokenCommitmentTooLong(
                maximum: maximumCommitmentByteCount,
                actual: commitment.count
            )
        }
    }
    
    static func validateDestination(_ destination: Address) throws {
        guard destination.supportsTokens else {
            throw Account.Error.tokenMutationRequiresTokenAwareAddress([destination])
        }
    }
}
