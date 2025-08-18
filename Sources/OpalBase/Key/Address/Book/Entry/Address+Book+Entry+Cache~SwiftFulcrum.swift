// Address+Book+Entry+Cache~SwiftFulcrum.swift

import Foundation
import SwiftFulcrum

extension Address.Book {
    func updateCache(using fulcrum: Fulcrum) async throws {
        let operation = { [self] in
            try await updateCache(in: receivingEntries, fulcrum: fulcrum)
            try await updateCache(in: changeEntries, fulcrum: fulcrum)
        }
        
        try await executeOrEnqueue(operation)
    }
    
    func updateCache(in entries: [Entry], fulcrum: Fulcrum) async throws {
        let operation = { [self] in
            for entry in entries where !entry.cache.isValid {
                let address = entry.address
                let latestBalance = try await address.fetchBalance(using: fulcrum)
                try updateCache(for: address, with: latestBalance)
            }
        }
        
        try await executeOrEnqueue(operation)
    }
}
