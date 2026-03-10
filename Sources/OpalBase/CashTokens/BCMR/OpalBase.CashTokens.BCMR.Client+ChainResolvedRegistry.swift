// OpalBase.CashTokens.BCMR.Client+ChainResolvedRegistry.swift

import Foundation

extension OpalBase.CashTokens.BCMR.Client {
    public struct ChainResolvedRegistry: Sendable {
        public let authbase: OpalBase.Transaction.Hash
        public let authhead: OpalBase.Transaction.Hash
        public let publication: Publication
        public let registry: Registry
        
        public init(
            authbase: OpalBase.Transaction.Hash,
            authhead: OpalBase.Transaction.Hash,
            publication: Publication,
            registry: Registry
        ) {
            self.authbase = authbase
            self.authhead = authhead
            self.publication = publication
            self.registry = registry
        }
    }

    public func resolveChainRegistry(authbase: OpalBase.Transaction.Hash) async throws -> ChainResolvedRegistry {
        let authhead = try await authchainResolver.resolveAuthhead(from: authbase)
        let transaction = try await fetchTransaction(for: authhead)
        guard let publication = findPublication(in: transaction) else {
            throw ChainRegistryResolverError.missingPublicationOutput(authhead)
        }
        
        let registryBytes = try await fetchRegistryBytes(for: publication, authhead: authhead)
        let registryHash = OpalCryptoAdapter.sha256(registryBytes)
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

private extension OpalBase.CashTokens.BCMR.Client {
    func fetchTransaction(for transactionHash: OpalBase.Transaction.Hash) async throws -> OpalBase.Transaction {
        let rawTransactionData = try await authchainResolver.transactionReader.fetchRawTransaction(
            for: transactionHash
        )
        do {
            return try OpalBase.Transaction.decode(from: rawTransactionData).transaction
        } catch {
            throw AuthchainResolver.Error.transactionDecodingFailed(transactionHash, error)
        }
    }
    
    func findPublication(in transaction: OpalBase.Transaction) -> Publication? {
        for output in transaction.outputs {
            if let publication = Self.parsePublicationOutput(lockingScript: output.lockingScript) {
                return publication
            }
        }
        return nil
    }
    
    func fetchRegistryBytes(
        for publication: Publication,
        authhead: OpalBase.Transaction.Hash
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
