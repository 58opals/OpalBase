// OpalBase.CashTokens.BCMR.Client+Error.swift

import Foundation

extension OpalBase.CashTokens.BCMR.Client {
    public enum Error: Swift.Error, Sendable {
        case registryDecodingFailed(Swift.Error)
        case invalidRegistryIdentity(String, Swift.Error)
    }
    
    public func importRegistry(from url: URL) async throws -> [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata] {
        let registryBytes = try await registryFetcher.fetchRegistryBytes(from: url.absoluteString)
        let registry = try decodeRegistryData(from: registryBytes)
        if let registryIdentity = registry.registryIdentity {
            let authbase = try parseRegistryIdentityHash(from: registryIdentity)
            let chainRegistry = try await resolveChainRegistry(authbase: authbase)
            return extractTokenMetadata(from: chainRegistry.registry, source: .chain(authbase))
        }
        return extractTokenMetadata(from: registry, source: .dns(url))
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
}

private enum RegistryIdentityHashValidationError: Swift.Error {
    case invalidByteCount(expected: Int, actual: Int)
}

