// TokenPrefixNonFungibleTokenData.swift

import Foundation

struct TokenPrefixNonFungibleTokenData: Codable, Sendable {
    let commitment: String
    let capability: String
}
