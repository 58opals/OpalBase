// Address+Book+Entry+Cache~FulcrumService.swift

import Foundation

extension Address.Book {
    func updateCache(using service: Network.FulcrumService) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            try await updateCache(in: .receiving, service: service)
                        try await updateCache(in: .change, service: service)
        }
        
        try await executeOrEnqueue(.updateCache, operation: operation)
    }
    
    func updateCache(in usage: DerivationPath.Usage, service: Network.FulcrumService) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            let entries = await listEntries(for: usage)
            for entry in entries where !entry.cache.isValid {
                let address = entry.address
                let latestBalance = try await service.balance(for: address, includeUnconfirmed: true)
                try await updateCache(for: address, with: latestBalance)
            }
        }
        
        let scope = Request.Scope(usage: usage)
        try await executeOrEnqueue(.updateCacheSubset(scope), operation: operation)
    }
}
