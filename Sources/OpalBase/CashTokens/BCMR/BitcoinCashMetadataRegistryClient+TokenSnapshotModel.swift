// BitcoinCashMetadataRegistryClient+TokenSnapshotModel.swift

import Foundation

extension BitcoinCashMetadataRegistryClient {
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
