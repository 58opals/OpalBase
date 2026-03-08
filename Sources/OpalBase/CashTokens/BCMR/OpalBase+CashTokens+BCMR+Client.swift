// OpalBase+CashTokens+BCMR+Client.swift

import Foundation

extension _OpalBase.CashTokens.BCMR {
    public struct Client {
        public let authchainResolver: AuthchainResolver
        public let registryFetcher: Fetcher

        public init(authchainResolver: AuthchainResolver, registryFetcher: Fetcher) {
            self.authchainResolver = authchainResolver
            self.registryFetcher = registryFetcher
        }
    }
}

extension _OpalBase.CashTokens.BCMR.Client {
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
}
