import Foundation
import SwiftFulcrum

extension Address.Book {
    public func updateCache(using fulcrum: Fulcrum) async throws {
        try await updateCache(in: receivingEntries, fulcrum: fulcrum)
        try await updateCache(in: changeEntries, fulcrum: fulcrum)
    }
    
    func updateCache(in entries: [Entry], fulcrum: Fulcrum) async throws {
        for entry in entries where !entry.cache.isValid {
            let address = entry.address
            let latestBalance = try await address.fetchBalance(using: fulcrum)
            try updateCache(for: address, with: latestBalance)
        }
    }
}
