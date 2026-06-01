// OpalBase+CashTokens+BCMR+Client+ChainResolvedRegistry.swift

import Foundation

extension OpalBase.CashTokens.BCMR.Client {
    public struct ChainResolvedRegistry: Sendable {
        public let authbase: OpalBase.Transaction.Hash
        public let authhead: OpalBase.Transaction.Hash
        public let publication: Publication
        public let registry: Registry
        public let registryFetchResult: Fetcher.RegistryFetchResult?
        
        public init(
            authbase: OpalBase.Transaction.Hash,
            authhead: OpalBase.Transaction.Hash,
            publication: Publication,
            registry: Registry,
            registryFetchResult: Fetcher.RegistryFetchResult? = nil
        ) {
            self.authbase = authbase
            self.authhead = authhead
            self.publication = publication
            self.registry = registry
            self.registryFetchResult = registryFetchResult
        }
    }

    public func resolveChainRegistry(authbase: OpalBase.Transaction.Hash) async throws -> ChainResolvedRegistry {
        let authhead = try await authchainResolver.resolveAuthhead(from: authbase)
        let transaction = try await fetchTransaction(for: authhead)
        guard let publication = findPublication(in: transaction) else {
            throw ChainRegistryResolverError.missingPublicationOutput(authhead)
        }
        
        let registryFetchResult = try await fetchRegistry(for: publication, authhead: authhead)
        let registry = try decodeRegistry(from: registryFetchResult.bytes)
        return ChainResolvedRegistry(
            authbase: authbase,
            authhead: authhead,
            publication: publication,
            registry: registry,
            registryFetchResult: registryFetchResult
        )
    }
}

private extension OpalBase.CashTokens.BCMR.Client {
    func fetchTransaction(for transactionHash: OpalBase.Transaction.Hash) async throws -> OpalBase.Transaction {
        let rawTransactionData = try await authchainResolver.transactionReader.fetchRawTransaction(
            for: transactionHash
        )
        return try AuthchainResolver.decodeTransaction(rawTransactionData, transactionHash: transactionHash)
    }
    
    func findPublication(in transaction: OpalBase.Transaction) -> Publication? {
        for output in transaction.outputs {
            if let publication = Self.parsePublicationOutput(lockingScript: output.lockingScript) {
                return publication
            }
        }
        return nil
    }
    
    func fetchRegistry(
        for publication: Publication,
        authhead: OpalBase.Transaction.Hash
    ) async throws -> OpalBase.CashTokens.BCMR.Client.Fetcher.RegistryFetchResult {
        guard !publication.uris.isEmpty else {
            throw ChainRegistryResolverError.noRegistryLocation(authhead)
        }

        var lastError: ChainRegistryResolverError?
        for uri in publication.uris {
            do {
                let registryFetchResult = try await registryFetcher.fetchRegistry(from: uri)
                let registryHash = OpalCryptoAdapter.sha256(registryFetchResult.bytes)
                guard registryHash == publication.sha256 else {
                    lastError = ChainRegistryResolverError.invalidRegistryHash(
                        expected: publication.sha256,
                        actual: registryHash
                    )
                    continue
                }
                return registryFetchResult
            } catch {
                lastError = ChainRegistryResolverError.registryFetchingFailed(uri, error)
            }
        }

        throw lastError ?? ChainRegistryResolverError.noRegistryLocation(authhead)
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
