// CashTokens+TokenData.swift

import Foundation

extension CashTokens {
    public struct TokenData: Codable, Hashable, Sendable {
        public let category: CategoryID
        public let amount: UInt64?
        public let nft: NFT?
        
        public init(category: CategoryID, amount: UInt64?, nft: NFT?) {
            self.category = category
            self.amount = amount
            self.nft = nft
        }
    }
}
