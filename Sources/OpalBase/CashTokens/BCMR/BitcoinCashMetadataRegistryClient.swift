// BitcoinCashMetadataRegistryClient.swift

import Foundation

public struct BitcoinCashMetadataRegistryClient {
    public let authchainResolver: AuthchainResolverModel
    public let registryFetcher: FetcherModel
    
    public init(authchainResolver: AuthchainResolverModel, registryFetcher: FetcherModel) {
        self.authchainResolver = authchainResolver
        self.registryFetcher = registryFetcher
    }
}

extension BitcoinCashMetadataRegistryClient {
    public struct RegistryModel: Codable, Sendable {
        public let version: String?
        public let registryIdentity: String?
        public let identities: [String: [String: IdentitySnapshotModel]]?
        
        public init(
            version: String?,
            registryIdentity: String?,
            identities: [String: [String: IdentitySnapshotModel]]?
        ) {
            self.version = version
            self.registryIdentity = registryIdentity
            self.identities = identities
        }
    }
}
