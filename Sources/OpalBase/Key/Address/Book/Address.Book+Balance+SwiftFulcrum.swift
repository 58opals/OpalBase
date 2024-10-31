import Foundation
import SwiftFulcrum

extension Address.Book {
    public func getBalanceFromBlockchain(address: Address, fulcrum: Fulcrum) async throws -> Satoshi {
        let newBalance = try await address.fetchBalance(using: fulcrum)
        try updateCache(for: address, with: newBalance)
        return newBalance
    }
}
