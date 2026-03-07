// BitcoinCashMetadataRegistryClient+ChainResolvedRegistryModel.swift

import Foundation

extension BitcoinCashMetadataRegistryClient {
    public struct ChainResolvedRegistryModel: Sendable {
        public let authbase: TransactionModel.HashModel
        public let authhead: TransactionModel.HashModel
        public let publication: PublicationModel
        public let registry: RegistryModel
        
        public init(
            authbase: TransactionModel.HashModel,
            authhead: TransactionModel.HashModel,
            publication: PublicationModel,
            registry: RegistryModel
        ) {
            self.authbase = authbase
            self.authhead = authhead
            self.publication = publication
            self.registry = registry
        }
    }
    
    public enum ChainRegistryResolverError: Swift.Error, Sendable {
        case missingPublicationOutput(TransactionModel.HashModel)
        case invalidRegistryHash(expected: Data, actual: Data)
        case registryDecodingFailed(Swift.Error)
        case registryFetchingFailed(String, Swift.Error)
        case noRegistryLocation(TransactionModel.HashModel)
    }
    
    public func resolveChainRegistry(authbase: TransactionModel.HashModel) async throws -> ChainResolvedRegistryModel {
        let authhead = try await authchainResolver.resolveAuthhead(from: authbase)
        let transaction = try await fetchTransaction(for: authhead)
        guard let publication = findPublication(in: transaction) else {
            throw ChainRegistryResolverError.missingPublicationOutput(authhead)
        }
        
        let registryBytes = try await fetchRegistryBytes(for: publication, authhead: authhead)
        let registryHash = SHA256Model.hash(registryBytes)
        guard registryHash == publication.sha256 else {
            throw ChainRegistryResolverError.invalidRegistryHash(
                expected: publication.sha256,
                actual: registryHash
            )
        }
        
        let registry = try decodeRegistry(from: registryBytes)
        return ChainResolvedRegistryModel(
            authbase: authbase,
            authhead: authhead,
            publication: publication,
            registry: registry
        )
    }
}

private extension BitcoinCashMetadataRegistryClient {
    func fetchTransaction(for transactionHash: TransactionModel.HashModel) async throws -> TransactionModel {
        let rawTransactionData = try await authchainResolver.transactionReader.fetchRawTransaction(
            for: transactionHash
        )
        do {
            return try TransactionModel.decode(from: rawTransactionData).transaction
        } catch {
            throw AuthchainResolverModel.Error.transactionDecodingFailed(transactionHash, error)
        }
    }
    
    func findPublication(in transaction: TransactionModel) -> PublicationModel? {
        for output in transaction.outputs {
            if let publication = Self.parsePublicationOutput(lockingScript: output.lockingScript) {
                return publication
            }
        }
        return nil
    }
    
    func fetchRegistryBytes(
        for publication: PublicationModel,
        authhead: TransactionModel.HashModel
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
    
    func decodeRegistry(from registryBytes: Data) throws -> RegistryModel {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(RegistryModel.self, from: registryBytes)
        } catch {
            throw ChainRegistryResolverError.registryDecodingFailed(error)
        }
    }
}

