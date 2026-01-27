// Wallet~BCMR.swift

import Foundation

extension Wallet {
    public func syncTokenMetadata(
        using transactionReader: Network.TransactionReadable,
        addressReader: Network.AddressReadable,
        scriptHashReader: Network.ScriptHashReadable? = nil,
        categories: Set<CashTokens.CategoryID>? = nil
    ) async throws {
        let targetCategories = try await resolveTokenCategories(from: categories)
        guard !targetCategories.isEmpty else { return }
        let metadataByCategory = await withTaskGroup(
            of: [CashTokens.CategoryID: TokenMetadata].self
        ) { group in
            for category in targetCategories {
                group.addTask {
                    let registries = Self.makeMetadataRegistries(
                        transactionReader: transactionReader,
                        addressReader: addressReader,
                        scriptHashReader: scriptHashReader
                    )
                    let authbase = Transaction.Hash(naturalOrder: category.transactionOrderData)
                    do {
                        let registry = try await registries.resolveChainRegistry(authbase: authbase)
                        return registries.extractTokenMetadata(
                            from: registry.registry,
                            source: .chain(authbase)
                        )
                    } catch {
                        return .init()
                    }
                }
            }
            
            var aggregatedMetadata: [CashTokens.CategoryID: TokenMetadata] = .init()
            for await registryMetadata in group {
                aggregatedMetadata.merge(registryMetadata) { current, _ in current }
            }
            return aggregatedMetadata
        }
        
        guard !metadataByCategory.isEmpty else { return }
        await tokenMetadataStore.upsert(metadataByCategory)
    }
}

private extension Wallet {
    func resolveTokenCategories(
        from categories: Set<CashTokens.CategoryID>?
    ) async throws -> Set<CashTokens.CategoryID> {
        if let categories {
            return categories
        }
        
        var aggregatedCategories = Set<CashTokens.CategoryID>()
        for account in accounts.values {
            let tokenInventory = try await account.loadTokenInventory()
            aggregatedCategories.formUnion(tokenInventory.fungibleAmountsByCategory.keys)
        }
        
        return aggregatedCategories
    }
    
    static func makeMetadataRegistries(
        transactionReader: Network.TransactionReadable,
        addressReader: Network.AddressReadable,
        scriptHashReader: Network.ScriptHashReadable?
    ) -> BitcoinCashMetadataRegistries {
        let authchainResolver = BitcoinCashMetadataRegistries.AuthchainResolver(
            transactionReader: transactionReader,
            addressReader: addressReader,
            scriptHashReader: scriptHashReader,
            maxDepth: 10
        )
        let registryFetcher = BitcoinCashMetadataRegistries.Fetcher(
            urlSession: .shared,
            ipfsGateway: nil,
            maxBytes: 1_000_000
        )
        return BitcoinCashMetadataRegistries(
            authchainResolver: authchainResolver,
            registryFetcher: registryFetcher
        )
    }
}
