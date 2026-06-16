// TokenMetadataSyncAuthbaseFixture.swift

import Foundation
@testable import OpalBase

struct TokenMetadataSyncAuthbaseFixture: Sendable {
    let rawTransaction: Data
    let transactionHash: OpalBase.Transaction.Hash
    let category: OpalBase.CashTokens.CategoryID
}
