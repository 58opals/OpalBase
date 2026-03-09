// OpalBase+Transaction+Output~Order.swift

import Foundation

extension _OpalBase.Transaction.Output {
    /// Returns the provided outputs using BIP-69 value and bytecode ordering.
    ///
    /// The specification requires sorting by the output value (ascending) and
    /// using the locking script bytes as a lexicographic tie breaker. When two
    /// token-bearing outputs still tie on those fields, this implementation
    /// applies token metadata tie breakers so token-aware builders keep a
    /// deterministic ordering instead of treating the outputs as equal.
    /// - Parameter outputs: The outputs to be ordered.
    /// - Returns: The outputs sorted by BIP-69 rules plus token-aware tie
    ///   breakers for equal locking bytecode.
    static func applyBIP69Ordering(_ outputs: [OpalBase.Transaction.Output]) -> [OpalBase.Transaction.Output] {
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
    
    private static func compareTokenData(lhs: OpalBase.CashTokens.TokenData?, rhs: OpalBase.CashTokens.TokenData?) -> Bool {
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
    
    private static func compareNonFungibleToken(lhs: OpalBase.CashTokens.NFT?, rhs: OpalBase.CashTokens.NFT?) -> Bool {
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
    
    private static func rankCapability(_ capability: OpalBase.CashTokens.NFT.Capability) -> Int {
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
