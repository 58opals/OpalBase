// OpalBase+Wallet~BCMR.swift

import Foundation
import OpalDiagnostics

extension _OpalBase.Wallet {
    public func syncTokenMetadata(
        using transactionReader: OpalBase.Network.TransactionReader,
        addressReader: OpalBase.Network.AddressReader,
        scriptHashReader: OpalBase.Network.ScriptHashReader? = nil,
        categories: Set<OpalBase.CashTokens.CategoryID>? = nil,
        registryFetcher: OpalBase.CashTokens.BCMR.Client.Fetcher? = nil
    ) async throws {
        try await OpalDiagnostics.withTraceID {
            OpalDiagnostics.record(
                OpalDiagnostics.Event.tokenMetadataSyncStarted,
                category: OpalDiagnostics.Category.tokenMetadata,
                fields: [
                    OpalDiagnostics.Field.operation("token_metadata_sync"),
                    OpalDiagnostics.Field.module()
                ]
            )

            do {
                let targetCategories = try await resolveTokenCategories(from: categories)
                guard !targetCategories.isEmpty else {
                    OpalDiagnostics.record(
                        OpalDiagnostics.Event.tokenMetadataSyncSucceeded,
                        category: OpalDiagnostics.Category.tokenMetadata,
                        fields: [
                            OpalDiagnostics.Field.operation("token_metadata_sync"),
                            OpalDiagnostics.Field.module(),
                            OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.tokenCategoryCount, 0),
                            OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.tokenMetadataCount, 0)
                        ]
                    )
                    return
                }
                let metadataByCategory = try await withThrowingTaskGroup(
                    of: [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata].self
                ) { group in
                    for category in targetCategories {
                        group.addTask {
                            let registries = Self.makeMetadataRegistries(
                                transactionReader: transactionReader,
                                addressReader: addressReader,
                                scriptHashReader: scriptHashReader,
                                registryFetcher: registryFetcher
                            )
                            let authbase = OpalBase.Transaction.Hash(naturalOrder: category.transactionOrderData)
                            do {
                                let registry = try await registries.resolveChainRegistry(authbase: authbase)
                                let metadata = registries.extractTokenMetadata(
                                    from: registry.registry,
                                    source: .chain(authbase)
                                )
                                return Self.applyDefaultRegistryURL(
                                    registry.registryFetchResult?.finalURL,
                                    to: metadata
                                )
                            } catch where OpalBaseCancellation.isCancellationError(error) {
                                throw CancellationError()
                            } catch {
                                return .init()
                            }
                        }
                    }

                    var aggregatedMetadata: [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata] = .init()
                    for try await registryMetadata in group {
                        aggregatedMetadata.merge(registryMetadata) { current, _ in current }
                    }
                    return aggregatedMetadata.filter { category, _ in
                        targetCategories.contains(category)
                    }
                }

                guard !metadataByCategory.isEmpty else {
                    OpalDiagnostics.record(
                        OpalDiagnostics.Event.tokenMetadataSyncSucceeded,
                        category: OpalDiagnostics.Category.tokenMetadata,
                        fields: [
                            OpalDiagnostics.Field.operation("token_metadata_sync"),
                            OpalDiagnostics.Field.module(),
                            OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.tokenCategoryCount, targetCategories.count),
                            OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.tokenMetadataCount, 0)
                        ]
                    )
                    return
                }
                await tokenMetadataStore.upsert(metadataByCategory)
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.tokenMetadataSyncSucceeded,
                    category: OpalDiagnostics.Category.tokenMetadata,
                    fields: [
                        OpalDiagnostics.Field.operation("token_metadata_sync"),
                        OpalDiagnostics.Field.module(),
                        OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.tokenCategoryCount, targetCategories.count),
                        OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.tokenMetadataCount, metadataByCategory.count)
                    ]
                )
            } catch {
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.tokenMetadataSyncFailed,
                    category: OpalDiagnostics.Category.tokenMetadata,
                    fields: [
                        OpalDiagnostics.Field.operation("token_metadata_sync"),
                        OpalDiagnostics.Field.module()
                    ] + OpalDiagnostics.Field.errorFields(
                        for: error,
                        fallback: OpalDiagnostics.ErrorCode.tokenMetadataSyncFailed
                    )
                )
                throw error
            }
        }
    }
}

private extension _OpalBase.Wallet {
    func resolveTokenCategories(
        from categories: Set<OpalBase.CashTokens.CategoryID>?
    ) async throws -> Set<OpalBase.CashTokens.CategoryID> {
        if let categories {
            return categories
        }
        
        var aggregatedCategories = Set<OpalBase.CashTokens.CategoryID>()
        for account in accounts.values {
            let tokenInventory = try await account.loadTokenInventory()
            aggregatedCategories.formUnion(tokenInventory.fungibleAmountsByCategory.keys)
            aggregatedCategories.formUnion(tokenInventory.nonFungibleTokensByGroup.keys.map(\.category))
        }
        
        return aggregatedCategories
    }
    
    static func makeMetadataRegistries(
        transactionReader: OpalBase.Network.TransactionReader,
        addressReader: OpalBase.Network.AddressReader,
        scriptHashReader: OpalBase.Network.ScriptHashReader?,
        registryFetcher: OpalBase.CashTokens.BCMR.Client.Fetcher?
    ) -> OpalBase.CashTokens.BCMR.Client {
        let authchainResolver = OpalBase.CashTokens.BCMR.Client.AuthchainResolver(
            transactionReader: transactionReader,
            addressReader: addressReader,
            scriptHashReader: scriptHashReader,
            maxDepth: 10
        )
        let registryFetcher = registryFetcher ?? OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: .shared,
            ipfsGateway: nil,
            maxBytes: 1_000_000
        )
        return OpalBase.CashTokens.BCMR.Client(
            authchainResolver: authchainResolver,
            registryFetcher: registryFetcher
        )
    }

    static func applyDefaultRegistryURL(
        _ registryURL: URL?,
        to metadataByCategory: [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata]
    ) -> [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata] {
        guard let registryURL else { return metadataByCategory }
        return metadataByCategory.mapValues { metadata in
            guard metadata.registryURL == nil else { return metadata }
            return OpalBase.CashTokens.Metadata(
                category: metadata.category,
                name: metadata.name,
                symbol: metadata.symbol,
                decimals: metadata.decimals,
                iconURL: metadata.iconURL,
                lastUpdated: metadata.lastUpdated,
                source: metadata.source,
                description: metadata.description,
                webURL: metadata.webURL,
                identity: metadata.identity,
                authbase: metadata.authbase,
                registryURL: registryURL
            )
        }
    }

}
