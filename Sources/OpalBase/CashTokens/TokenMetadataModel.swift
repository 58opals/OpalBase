// TokenMetadataModel.swift

import Foundation

public struct TokenMetadataModel: Codable, Equatable, Sendable {
    public let category: CashTokensModel.CategoryIDModel
    public let name: String?
    public let symbol: String?
    public let decimals: Int?
    public let iconURL: URL?
    public let lastUpdated: Date
    public let source: Source
    
    public enum Source: Codable, Equatable, Sendable {
        case embedded
        case dns(URL)
        case chain(TransactionModel.HashModel)
    }
}
