// BroadcastHashExpectation.swift

import Foundation
import Testing
@testable import OpalBase

enum BroadcastHashExpectation {
    static func makeHash(from broadcasts: [String]) throws -> OpalBase.Transaction.Hash {
        let rawTransactionHexadecimal = try #require(broadcasts.first)
        let rawTransactionData = try Data(hexadecimalString: rawTransactionHexadecimal)
        return OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(rawTransactionData)
        )
    }
}
