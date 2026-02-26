// BCMR.swift

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
    
    public struct IdentitySnapshotModel: Codable, Sendable {
        public let name: String?
        public let description: String?
        public let token: TokenSnapshotModel?
        public let uris: [String: String]?
        
        public init(
            name: String?,
            description: String?,
            token: TokenSnapshotModel?,
            uris: [String: String]?
        ) {
            self.name = name
            self.description = description
            self.token = token
            self.uris = uris
        }
    }
    
    public struct TokenSnapshotModel: Codable, Sendable {
        public let category: String?
        public let symbol: String?
        public let decimals: Int?
        
        public init(category: String?, symbol: String?, decimals: Int?) {
            self.category = category
            self.symbol = symbol
            self.decimals = decimals
        }
    }
}
