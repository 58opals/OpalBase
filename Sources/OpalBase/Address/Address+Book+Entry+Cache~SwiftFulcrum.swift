// Address+Book+Entry+Cache~SwiftFulcrum.swift

import Foundation
import SwiftFulcrum

extension Address.Book {
    func updateCache(using fulcrum: Fulcrum) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            try await updateCache(in: .receiving, fulcrum: fulcrum)
            try await updateCache(in: .change, fulcrum: fulcrum)
        }
        
        try await executeOrEnqueue(.updateCache, operation: operation)
    }
    
    func updateCache(in usage: DerivationPath.Usage, fulcrum: Fulcrum) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            let entries = await listEntries(for: usage)
            for entry in entries where !entry.cache.isValid {
                let address = entry.address
                let latestBalance = try await address.fetchBalance(using: fulcrum)
                try await updateCache(for: address, with: latestBalance)
            }
        }
        
        let scope = Request.Scope(usage: usage)
        try await executeOrEnqueue(.updateCacheSubset(scope), operation: operation)
    }
}
