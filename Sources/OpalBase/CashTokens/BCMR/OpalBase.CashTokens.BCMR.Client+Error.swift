// OpalBase.CashTokens.BCMR.Client+Error.swift

import Foundation

extension OpalBase.CashTokens.BCMR.Client {
    public enum Error: Swift.Error, Sendable {
        case registryDecodingFailed(Swift.Error)
        case invalidRegistryIdentity(String, Swift.Error)
    }

    public func importRegistry(from url: URL) async throws -> [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata] {
        try await importRegistry(from: url.absoluteString)
    }

    public func importRegistry(from resourceIdentifier: String) async throws -> [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata] {
        let registryFetchResult = try await registryFetcher.fetchRegistry(from: resourceIdentifier)
        let registry = try decodeRegistryData(from: registryFetchResult.bytes)
        if let registryIdentity = registry.registryIdentity {
            let authbase = try parseRegistryIdentityHash(from: registryIdentity)
            let chainRegistry = try await resolveChainRegistry(authbase: authbase)
            return applyDefaultRegistryURL(
                chainRegistry.registryFetchResult?.finalURL,
                to: extractTokenMetadata(from: chainRegistry.registry, source: .chain(authbase))
            )
        }
        return applyDefaultRegistryURL(
            registryFetchResult.finalURL,
            to: extractTokenMetadata(from: registry, source: .dns(registryFetchResult.finalURL))
        )
    }
    
    public func addEmbeddedRegistry(data: Data) throws -> [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata] {
        let registry = try decodeRegistryData(from: data)
        return extractTokenMetadata(from: registry, source: .embedded)
    }
}

private extension OpalBase.CashTokens.BCMR.Client {
    func decodeRegistryData(from registryBytes: Data) throws -> Registry {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(Registry.self, from: registryBytes)
        } catch {
            throw Error.registryDecodingFailed(error)
        }
    }
    
    func parseRegistryIdentityHash(from registryIdentity: String) throws -> OpalBase.Transaction.Hash {
        let data: Data
        do {
            data = try Data(hexadecimalString: registryIdentity)
        } catch {
            throw Error.invalidRegistryIdentity(registryIdentity, error)
        }
        
        guard data.count == OpalBase.Transaction.Hash.expectedByteCount else {
            throw Error.invalidRegistryIdentity(
                registryIdentity,
                RegistryIdentityHashValidationError.invalidByteCount(
                    expected: OpalBase.Transaction.Hash.expectedByteCount,
                    actual: data.count
                )
            )
        }
        
        return OpalBase.Transaction.Hash(dataFromRPC: data)
    }

    func applyDefaultRegistryURL(
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

private enum RegistryIdentityHashValidationError: Swift.Error {
    case invalidByteCount(expected: Int, actual: Int)
}
