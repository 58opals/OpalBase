// CashTokensModel+TokenData~Fulcrum.swift

import Foundation
import SwiftFulcrum

extension CashTokensModel.TokenData {
    init(swiftFulcrumTokenData: SwiftFulcrum.RPC.Method.Blockchain.CashTokens.JSON) throws {
        let category = try CashTokensModel.CategoryIDModel(hexFromRPC: swiftFulcrumTokenData.category)
        let amount = try Self.parseAmount(from: swiftFulcrumTokenData.amount)
        let nft = try swiftFulcrumTokenData.nft.map { try CashTokensModel.NFTModel(swiftFulcrumNFT: $0) }
        self.init(category: category, amount: amount, nft: nft)
    }
    
    private static func parseAmount(from amountString: String) throws -> UInt64? {
        guard let amountValue = UInt64(amountString) else {
            throw CashTokensModel.Error.invalidFungibleAmountString(amountString)
        }
        return amountValue == 0 ? nil : amountValue
    }
}

private extension CashTokensModel.NFTModel {
    init(swiftFulcrumNFT: SwiftFulcrum.RPC.Method.Blockchain.CashTokens.JSON.NFT) throws {
        let capability = CashTokensModel.NFTModel.Capability(swiftFulcrumCapability: swiftFulcrumNFT.capability)
        let commitment: Data
        do {
            commitment = try Data(hexadecimalString: swiftFulcrumNFT.commitment)
        } catch {
            throw CashTokensModel.Error.invalidHexadecimalString
        }
        try self.init(capability: capability, commitment: commitment)
    }
}

private extension CashTokensModel.NFTModel.Capability {
    init(swiftFulcrumCapability: SwiftFulcrum.RPC.Method.Blockchain.CashTokens.JSON.NFT.Capability) {
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
