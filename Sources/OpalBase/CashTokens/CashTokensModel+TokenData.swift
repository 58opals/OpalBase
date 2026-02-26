// CashTokensModel+TokenData.swift

import Foundation

extension CashTokensModel {
    public struct TokenData: Codable, Hashable, Sendable {
        public let category: CategoryIDModel
        public let amount: UInt64?
        public let nft: NFTModel?
        
        public init(category: CategoryIDModel, amount: UInt64?, nft: NFTModel?) {
            self.category = category
            self.amount = amount
            self.nft = nft
        }
    }
}
