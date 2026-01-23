// CashTokens~Fulcrum.swift

import Foundation
import SwiftFulcrum

extension CashTokens.TokenData {
    public init(swiftFulcrumTokenData: SwiftFulcrum.Method.Blockchain.CashTokens.JSON) throws {
        let category = try CashTokens.CategoryID(hexFromRPC: swiftFulcrumTokenData.category)
        let amount = try Self.parseAmount(from: swiftFulcrumTokenData.amount)
        let nft = try swiftFulcrumTokenData.nft.map { try CashTokens.NFT(swiftFulcrumNFT: $0) }
        self.init(category: category, amount: amount, nft: nft)
    }
    
    private static func parseAmount(from amountString: String) throws -> UInt64? {
        guard let amountValue = UInt64(amountString) else {
            throw CashTokens.Error.invalidFungibleAmountString(amountString)
        }
        return amountValue == 0 ? nil : amountValue
    }
}

private extension CashTokens.NFT {
    init(swiftFulcrumNFT: SwiftFulcrum.Method.Blockchain.CashTokens.JSON.NFT) throws {
        let capability = CashTokens.NFT.Capability(swiftFulcrumCapability: swiftFulcrumNFT.capability)
        let commitment: Data
        do {
            commitment = try Data(hexadecimalString: swiftFulcrumNFT.commitment)
        } catch {
            throw CashTokens.Error.invalidHexadecimalString
        }
        try self.init(capability: capability, commitment: commitment)
    }
}

private extension CashTokens.NFT.Capability {
    init(swiftFulcrumCapability: SwiftFulcrum.Method.Blockchain.CashTokens.JSON.NFT.Capability) {
        switch swiftFulcrumCapability {
        case .none:
            self = .none
        case .mutable:
            self = .mutable
        case .minting:
            self = .minting
        }
    }
}
