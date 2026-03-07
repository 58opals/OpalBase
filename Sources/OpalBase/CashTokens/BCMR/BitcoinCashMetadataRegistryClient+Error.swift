// BitcoinCashMetadataRegistryClient+Error.swift

import Foundation

extension BitcoinCashMetadataRegistryClient {
    public enum Error: Swift.Error, Sendable {
        case registryDecodingFailed(Swift.Error)
        case invalidRegistryIdentity(String, Swift.Error)
    }
    
    public func importRegistry(from url: URL) async throws -> [OpalBase.CashTokens.CategoryIDModel: TokenMetadataModel] {
        let registryBytes = try await registryFetcher.fetchRegistryBytes(from: url.absoluteString)
        let registry = try decodeRegistryData(from: registryBytes)
        if let registryIdentity = registry.registryIdentity {
            let authbase = try parseRegistryIdentityHash(from: registryIdentity)
            let chainRegistry = try await resolveChainRegistry(authbase: authbase)
            return extractTokenMetadata(from: chainRegistry.registry, source: .chain(authbase))
        }
        return extractTokenMetadata(from: registry, source: .dns(url))
    }
    
    public func addEmbeddedRegistry(data: Data) throws -> [OpalBase.CashTokens.CategoryIDModel: TokenMetadataModel] {
        let registry = try decodeRegistryData(from: data)
        return extractTokenMetadata(from: registry, source: .embedded)
    }
}

private extension BitcoinCashMetadataRegistryClient {
    func decodeRegistryData(from registryBytes: Data) throws -> RegistryModel {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(RegistryModel.self, from: registryBytes)
        } catch {
            throw Error.registryDecodingFailed(error)
        }
    }
    
    func parseRegistryIdentityHash(from registryIdentity: String) throws -> OpalBase.Transaction.HashModel {
        let data: Data
        do {
            data = try Data(hexadecimalString: registryIdentity)
        } catch {
            throw Error.invalidRegistryIdentity(registryIdentity, error)
        }
        
        guard data.count == OpalBase.Transaction.HashModel.expectedByteCount else {
            throw Error.invalidRegistryIdentity(
                registryIdentity,
                RegistryIdentityHashValidationError.invalidByteCount(
                    expected: OpalBase.Transaction.HashModel.expectedByteCount,
                    actual: data.count
                )
            )
        }
        
        return OpalBase.Transaction.HashModel(dataFromRPC: data)
    }
}

private enum RegistryIdentityHashValidationError: Swift.Error {
    case invalidByteCount(expected: Int, actual: Int)
}

