// OpalBase+CashTokens+TokenData.swift

import Foundation

extension _OpalBase.CashTokens {
    public struct TokenData: Codable, Hashable, Sendable {
        public let category: CategoryID
        public let amount: UInt64?
        public let nft: NFT?

        static let maximumFungibleAmount: UInt64 = 0x7fff_ffff_ffff_ffff
        
        public init(category: CategoryID, amount: UInt64?, nft: NFT?) {
            self.category = category
            self.amount = amount
            self.nft = nft
        }
    }
}
