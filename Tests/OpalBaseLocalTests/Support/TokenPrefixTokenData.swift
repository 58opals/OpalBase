// TokenPrefixTokenData.swift

import Foundation

struct TokenPrefixTokenData: Codable {
    let category: String
    let amount: String?
    let nonFungibleToken: TokenPrefixNonFungibleTokenData?

    enum CodingKeys: String, CodingKey {
        case category
        case amount
        case nonFungibleToken = "nft"
    }
}

