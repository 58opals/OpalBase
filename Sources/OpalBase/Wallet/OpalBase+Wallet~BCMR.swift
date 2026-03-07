// OpalBase.Wallet~BCMR.swift

import Foundation

extension _OpalBase.Wallet {
    public func syncTokenMetadata(
        using transactionReader: OpalBase.Network.TransactionReadableClient,
        addressReader: OpalBase.Network.AddressReadable,
        scriptHashReader: OpalBase.Network.ScriptHashReadableClient? = nil,
        categories: Set<OpalBase.CashTokens.CategoryIDModel>? = nil
    ) async throws {
        let targetCategories = try await resolveTokenCategories(from: categories)
        guard !targetCategories.isEmpty else { return }
        let metadataByCategory = await withTaskGroup(
            of: [OpalBase.CashTokens.CategoryIDModel: TokenMetadataModel].self
        ) { group in
            for category in targetCategories {
                group.addTask {
                    let registries = Self.makeMetadataRegistries(
                        transactionReader: transactionReader,
                        addressReader: addressReader,
                        scriptHashReader: scriptHashReader
                    )
                    let authbase = OpalBase.Transaction.HashModel(naturalOrder: category.transactionOrderData)
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
            
            var aggregatedMetadata: [OpalBase.CashTokens.CategoryIDModel: TokenMetadataModel] = .init()
            for await registryMetadata in group {
                aggregatedMetadata.merge(registryMetadata) { current, _ in current }
            }
            return aggregatedMetadata
        }
        
        guard !metadataByCategory.isEmpty else { return }
        await tokenMetadataStore.upsert(metadataByCategory)
    }
}

private extension _OpalBase.Wallet {
    func resolveTokenCategories(
        from categories: Set<OpalBase.CashTokens.CategoryIDModel>?
    ) async throws -> Set<OpalBase.CashTokens.CategoryIDModel> {
        if let categories {
            return categories
        }
        
        var aggregatedCategories = Set<OpalBase.CashTokens.CategoryIDModel>()
        for account in accounts.values {
            let tokenInventory = try await account.loadTokenInventory()
            aggregatedCategories.formUnion(tokenInventory.fungibleAmountsByCategory.keys)
        }
        
        return aggregatedCategories
    }
    
    static func makeMetadataRegistries(
        transactionReader: OpalBase.Network.TransactionReadableClient,
        addressReader: OpalBase.Network.AddressReadable,
        scriptHashReader: OpalBase.Network.ScriptHashReadableClient?
    ) -> BitcoinCashMetadataRegistryClient {
        let authchainResolver = BitcoinCashMetadataRegistryClient.AuthchainResolverModel(
            transactionReader: transactionReader,
            addressReader: addressReader,
            scriptHashReader: scriptHashReader,
            maxDepth: 10
        )
        let registryFetcher = BitcoinCashMetadataRegistryClient.FetcherModel(
            urlSession: .shared,
            ipfsGateway: nil,
            maxBytes: 1_000_000
        )
        return BitcoinCashMetadataRegistryClient(
            authchainResolver: authchainResolver,
            registryFetcher: registryFetcher
        )
    }
}
