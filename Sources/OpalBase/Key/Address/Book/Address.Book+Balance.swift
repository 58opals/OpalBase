import Foundation

extension Address.Book {
    func getBalanceFromCache() throws -> Satoshi {
        let allEntries = receivingEntries + changeEntries
        let totalBalance = allEntries.map { $0.cache.balance.uint64 }.reduce(0, +)
        return try Satoshi(totalBalance)
    }
    
    mutating func getBalance(for address: Address, updateCacheBalance: Bool = false) async throws -> Satoshi {
        guard let entry = findEntry(for: address) else { throw Error.entryNotFound }
        if updateCacheBalance, !entry.cache.isValid {
            let newBalance = try await address.fetchBalance(using: fulcrum)
            try updateCache(for: address, with: newBalance)
            return newBalance
        } else {
            return entry.cache.balance
        }
    }
}
