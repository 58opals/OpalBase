// OpalBase+Account+TokenCommitmentMutation.swift

import Foundation

extension _OpalBase.Account {
        public struct TokenCommitmentMutation: Sendable {
        public enum Target: Sendable {
            case preferredInput(OpalBase.Transaction.Output.Unspent)
            case byGroup(OpalBase.Account.TokenInventory.NonFungibleTokenGroup)
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
            try TokenCommitmentMutationValidation.validateCommitment(newCommitment)
            try TokenCommitmentMutationValidation.validateDestination(destination)
            self.target = target
            self.newCommitment = Data(newCommitment)
            self.destination = destination
            self.bchAmount = bchAmount
            self.shouldPreserveAttachedFungibleToWallet = shouldPreserveAttachedFungibleToWallet
            self.feeOverride = feeOverride
            self.feeContext = feeContext
            self.shouldAllowDustDonation = shouldAllowDustDonation
        }
    }
}
