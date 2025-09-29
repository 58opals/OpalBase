// Address+Book+Entry+Cache~WalletNode.swift

import Foundation

extension Address.Book {
    func updateCache(using node: any Network.Wallet.Node) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            try await updateCache(in: .receiving, node: node)
            try await updateCache(in: .change, node: node)
        }
        
        try await executeOrEnqueue(.updateCache, operation: operation)
    }
    
    func updateCache(in usage: DerivationPath.Usage, node: any Network.Wallet.Node) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            let entries = await listEntries(for: usage)
            for entry in entries where !entry.cache.isValid {
                let address = entry.address
                let latestBalance = try await node.balance(for: address, includeUnconfirmed: true)
                try await updateCache(for: address, with: latestBalance)
            }
        }
        
        let scope = Request.Scope(usage: usage)
        try await executeOrEnqueue(.updateCacheSubset(scope), operation: operation)
    }
}
