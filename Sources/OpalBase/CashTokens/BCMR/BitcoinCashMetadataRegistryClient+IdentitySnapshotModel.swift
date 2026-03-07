// BitcoinCashMetadataRegistryClient+IdentitySnapshotModel.swift

import Foundation

extension BitcoinCashMetadataRegistryClient {
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
}
