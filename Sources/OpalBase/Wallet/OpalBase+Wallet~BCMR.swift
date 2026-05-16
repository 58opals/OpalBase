// OpalBase+Wallet~BCMR.swift

import Foundation

extension _OpalBase.Wallet {
    public func syncTokenMetadata(
        using transactionReader: OpalBase.Network.TransactionReader,
        addressReader: OpalBase.Network.AddressReader,
        scriptHashReader: OpalBase.Network.ScriptHashReader? = nil,
        categories: Set<OpalBase.CashTokens.CategoryID>? = nil,
        registryFetcher: OpalBase.CashTokens.BCMR.Client.Fetcher? = nil
    ) async throws {
        try await OpalBase.Diagnostics.withTraceID {
            OpalBaseDiagnostics.record(
                OpalBase.Diagnostics.Events.tokenMetadataSyncStarted,
                category: OpalBase.Diagnostics.Categories.tokenMetadata,
                fields: [
                    OpalBaseDiagnostics.operationField("token_metadata_sync"),
                    OpalBaseDiagnostics.moduleField()
                ]
            )

            do {
                let targetCategories = try await resolveTokenCategories(from: categories)
                guard !targetCategories.isEmpty else {
                    OpalBaseDiagnostics.record(
                        OpalBase.Diagnostics.Events.tokenMetadataSyncSucceeded,
                        category: OpalBase.Diagnostics.Categories.tokenMetadata,
                        fields: [
                            OpalBaseDiagnostics.operationField("token_metadata_sync"),
                            OpalBaseDiagnostics.moduleField(),
                            OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.tokenCategoryCount, 0),
                            OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.tokenMetadataCount, 0)
                        ]
                    )
                    return
                }
                let metadataByCategory = await withTaskGroup(
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
                            } catch {
                                return .init()
                            }
                        }
                    }

                    var aggregatedMetadata: [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata] = .init()
                    for await registryMetadata in group {
                        aggregatedMetadata.merge(registryMetadata) { current, _ in current }
                    }
                    return aggregatedMetadata.filter { category, _ in
                        targetCategories.contains(category)
                    }
                }

                guard !metadataByCategory.isEmpty else {
                    OpalBaseDiagnostics.record(
                        OpalBase.Diagnostics.Events.tokenMetadataSyncSucceeded,
                        category: OpalBase.Diagnostics.Categories.tokenMetadata,
                        fields: [
                            OpalBaseDiagnostics.operationField("token_metadata_sync"),
                            OpalBaseDiagnostics.moduleField(),
                            OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.tokenCategoryCount, targetCategories.count),
                            OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.tokenMetadataCount, 0)
                        ]
                    )
                    return
                }
                await tokenMetadataStore.upsert(metadataByCategory)
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.tokenMetadataSyncSucceeded,
                    category: OpalBase.Diagnostics.Categories.tokenMetadata,
                    fields: [
                        OpalBaseDiagnostics.operationField("token_metadata_sync"),
                        OpalBaseDiagnostics.moduleField(),
                        OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.tokenCategoryCount, targetCategories.count),
                        OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.tokenMetadataCount, metadataByCategory.count)
                    ]
                )
            } catch {
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.tokenMetadataSyncFailed,
                    category: OpalBase.Diagnostics.Categories.tokenMetadata,
                    fields: [
                        OpalBaseDiagnostics.operationField("token_metadata_sync"),
                        OpalBaseDiagnostics.moduleField()
                    ] + OpalBaseDiagnostics.errorFields(
                        for: error,
                        fallback: OpalBase.Diagnostics.ErrorCodes.tokenMetadataSyncFailed
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
