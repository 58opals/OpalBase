// TokenMetadata.swift

import Foundation

public struct TokenMetadata: Codable, Equatable, Sendable {
    public let category: CashTokens.CategoryID
    public let name: String?
    public let symbol: String?
    public let decimals: Int?
    public let iconURL: URL?
    public let lastUpdated: Date
    public let source: Source
    
    public enum Source: Codable, Equatable, Sendable {
        case embedded
        case dns(URL)
        case chain(Transaction.Hash)
    }
}
