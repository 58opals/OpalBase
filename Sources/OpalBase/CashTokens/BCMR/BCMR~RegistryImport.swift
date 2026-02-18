// BCMR~RegistryImport.swift

import Foundation

extension BitcoinCashMetadataRegistries {
    public enum Error: Swift.Error, Sendable {
        case registryDecodingFailed(Swift.Error)
        case invalidRegistryIdentity(String, Swift.Error)
    }
    
    public func importRegistry(from url: URL) async throws -> [CashTokens.CategoryID: TokenMetadata] {
        let registryBytes = try await registryFetcher.fetchRegistryBytes(from: url.absoluteString)
        let registry = try decodeRegistryData(from: registryBytes)
        if let registryIdentity = registry.registryIdentity {
            let authbase = try parseRegistryIdentityHash(from: registryIdentity)
            let chainRegistry = try await resolveChainRegistry(authbase: authbase)
            return extractTokenMetadata(from: chainRegistry.registry, source: .chain(authbase))
        }
        return extractTokenMetadata(from: registry, source: .dns(url))
    }
    
    public func addEmbeddedRegistry(data: Data) throws -> [CashTokens.CategoryID: TokenMetadata] {
        let registry = try decodeRegistryData(from: data)
        return extractTokenMetadata(from: registry, source: .embedded)
    }
}

private extension BitcoinCashMetadataRegistries {
    func decodeRegistryData(from registryBytes: Data) throws -> Registry {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(Registry.self, from: registryBytes)
        } catch {
            throw Error.registryDecodingFailed(error)
        }
    }
    
    func parseRegistryIdentityHash(from registryIdentity: String) throws -> Transaction.Hash {
        do {
            let data = try Data(hexadecimalString: registryIdentity)
            return Transaction.Hash(dataFromRPC: data)
        } catch {
            throw Error.invalidRegistryIdentity(registryIdentity, error)
        }
    }
}
