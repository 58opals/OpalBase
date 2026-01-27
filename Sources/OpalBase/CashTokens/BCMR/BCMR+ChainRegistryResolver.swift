// BCMR+ChainRegistryResolver.swift

import Foundation

extension BitcoinCashMetadataRegistries {
    public struct ChainResolvedRegistry: Sendable {
        public let authbase: Transaction.Hash
        public let authhead: Transaction.Hash
        public let publication: Publication
        public let registry: Registry
        
        public init(
            authbase: Transaction.Hash,
            authhead: Transaction.Hash,
            publication: Publication,
            registry: Registry
        ) {
            self.authbase = authbase
            self.authhead = authhead
            self.publication = publication
            self.registry = registry
        }
    }
    
    public enum ChainRegistryResolverError: Swift.Error, Sendable {
        case missingPublicationOutput(Transaction.Hash)
        case invalidRegistryHash(expected: Data, actual: Data)
        case registryDecodingFailed(Swift.Error)
        case registryFetchingFailed(String, Swift.Error)
        case noRegistryLocation(Transaction.Hash)
    }
    
    public func resolveChainRegistry(authbase: Transaction.Hash) async throws -> ChainResolvedRegistry {
        let authhead = try await authchainResolver.resolveAuthhead(from: authbase)
        let transaction = try await fetchTransaction(for: authhead)
        guard let publication = findPublication(in: transaction) else {
            throw ChainRegistryResolverError.missingPublicationOutput(authhead)
        }
        
        let registryBytes = try await fetchRegistryBytes(for: publication, authhead: authhead)
        let registryHash = SHA256.hash(registryBytes)
        guard registryHash == publication.sha256 else {
            throw ChainRegistryResolverError.invalidRegistryHash(
                expected: publication.sha256,
                actual: registryHash
            )
        }
        
        let registry = try decodeRegistry(from: registryBytes)
        return ChainResolvedRegistry(
            authbase: authbase,
            authhead: authhead,
            publication: publication,
            registry: registry
        )
    }
}

private extension BitcoinCashMetadataRegistries {
    func fetchTransaction(for transactionHash: Transaction.Hash) async throws -> Transaction {
        let rawTransactionData = try await authchainResolver.transactionReader.fetchRawTransaction(
            for: transactionHash
        )
        do {
            return try Transaction.decode(from: rawTransactionData).transaction
        } catch {
            throw AuthchainResolver.Error.transactionDecodingFailed(transactionHash, error)
        }
    }
    
    func findPublication(in transaction: Transaction) -> Publication? {
        for output in transaction.outputs {
            if let publication = Self.parsePublicationOutput(lockingScript: output.lockingScript) {
                return publication
            }
        }
        return nil
    }
    
    func fetchRegistryBytes(
        for publication: Publication,
        authhead: Transaction.Hash
    ) async throws -> Data {
        guard let uri = publication.uris.first else {
            throw ChainRegistryResolverError.noRegistryLocation(authhead)
        }
        
        do {
            return try await registryFetcher.fetchRegistryBytes(from: uri)
        } catch {
            throw ChainRegistryResolverError.registryFetchingFailed(uri, error)
        }
    }
    
    func decodeRegistry(from registryBytes: Data) throws -> Registry {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(Registry.self, from: registryBytes)
        } catch {
            throw ChainRegistryResolverError.registryDecodingFailed(error)
        }
    }
}
