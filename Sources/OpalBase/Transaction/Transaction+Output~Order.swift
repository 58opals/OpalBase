// Transaction+Output~Order.swift

import Foundation

extension Transaction.Output {
    /// Returns the provided outputs ordered according to BIP-69.
    ///
    /// The specification requires sorting by the output value (ascending) and
    /// using the locking script bytes as a lexicographic tie breaker. Applying
    /// this ordering yields deterministic transactions that are compatible with
    /// downstream tooling expecting canonical output layouts.
    /// - Parameter outputs: The outputs to be ordered.
    /// - Returns: The outputs sorted according to the canonical BIP-69 rules.
    static func applyBIP69Ordering(_ outputs: [Transaction.Output]) -> [Transaction.Output] {
        let shouldCompareTokenData = outputs.contains { $0.tokenData != nil }
        return outputs.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value < rhs.value
            }
            
            if lhs.lockingScript != rhs.lockingScript {
                return lhs.lockingScript.lexicographicallyPrecedes(rhs.lockingScript)
            }
            
            guard shouldCompareTokenData else { return false }
            
            return compareTokenData(lhs: lhs.tokenData, rhs: rhs.tokenData)
        }
    }
    
    private static func compareTokenData(lhs: CashTokens.TokenData?, rhs: CashTokens.TokenData?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return false
        case (nil, _):
            return true
        case (_, nil):
            return false
        case (let left?, let right?):
            if left.amount != right.amount {
                return compareOptionalAmount(lhs: left.amount, rhs: right.amount)
            }
            
            if left.nft != right.nft {
                return compareNonFungibleToken(lhs: left.nft, rhs: right.nft)
            }
            
            if left.category != right.category {
                return left.category.transactionOrderData.lexicographicallyPrecedes(right.category.transactionOrderData)
            }
            
            return false
        }
    }
    
    private static func compareOptionalAmount(lhs: UInt64?, rhs: UInt64?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return false
        case (nil, _):
            return true
        case (_, nil):
            return false
        case (let left?, let right?):
            return left < right
        }
    }
    
    private static func compareNonFungibleToken(lhs: CashTokens.NFT?, rhs: CashTokens.NFT?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return false
        case (nil, _):
            return true
        case (_, nil):
            return false
        case (let left?, let right?):
            let leftCapabilityRank = rankCapability(left.capability)
            let rightCapabilityRank = rankCapability(right.capability)
            if leftCapabilityRank != rightCapabilityRank {
                return leftCapabilityRank < rightCapabilityRank
            }
            
            if left.commitment != right.commitment {
                return left.commitment.lexicographicallyPrecedes(right.commitment)
            }
            
            return false
        }
    }
    
    private static func rankCapability(_ capability: CashTokens.NFT.Capability) -> Int {
        switch capability {
        case .none:
            return 0
        case .mutable:
            return 1
        case .minting:
            return 2
        }
    }
}
