// BCMR.swift

import Foundation

public enum BitcoinCashMetadataRegistries {}

extension BitcoinCashMetadataRegistries {
    public struct Registry: Codable, Sendable {
        public let version: String?
        public let registryIdentity: String?
        public let identities: [String: [String: IdentitySnapshot]]?
        
        public init(
            version: String?,
            registryIdentity: String?,
            identities: [String: [String: IdentitySnapshot]]?
        ) {
            self.version = version
            self.registryIdentity = registryIdentity
            self.identities = identities
        }
    }
    
    public struct IdentitySnapshot: Codable, Sendable {
        public let name: String?
        public let description: String?
        public let token: TokenSnapshot?
        public let uris: [String: String]?
        
        public init(
            name: String?,
            description: String?,
            token: TokenSnapshot?,
            uris: [String: String]?
        ) {
            self.name = name
            self.description = description
            self.token = token
            self.uris = uris
        }
    }
    
    public struct TokenSnapshot: Codable, Sendable {
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
