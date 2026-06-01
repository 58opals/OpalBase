// OpalBase+CashTokens+BCMR+Client+IdentitySnapshot.swift

extension OpalBase.CashTokens.BCMR.Client {
    public struct IdentitySnapshot: Codable, Sendable {
        public let name: String?
        public let description: String?
        public let migrated: String?
        public let token: TokenSnapshot?
        public let uris: [String: String]?
        
        public init(
            name: String?,
            description: String?,
            migrated: String? = nil,
            token: TokenSnapshot?,
            uris: [String: String]?
        ) {
            self.name = name
            self.description = description
            self.migrated = migrated
            self.token = token
            self.uris = uris
        }
    }
}
