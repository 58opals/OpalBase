// OpalBase+CashTokens+TokenData~Fulcrum.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.CashTokens.TokenData {
    init(swiftFulcrumTokenData: SwiftFulcrum.CashTokens.TokenData) throws {
        let category = try OpalBase.CashTokens.CategoryID(hexFromRPC: swiftFulcrumTokenData.category)
        let amount = try Self.parseAmount(from: swiftFulcrumTokenData.amount)
        let nft = try swiftFulcrumTokenData.nft.map { try OpalBase.CashTokens.NFT(swiftFulcrumNFT: $0) }
        guard amount != nil || nft != nil else {
            throw OpalBase.CashTokens.Error.invalidTokenPrefix
        }
        self.init(category: category, amount: amount, nft: nft)
    }
    
    private static func parseAmount(from amountString: String) throws -> UInt64? {
        guard let amountValue = UInt64(amountString) else {
            throw OpalBase.CashTokens.Error.invalidFungibleAmountString(amountString)
        }
        guard amountValue <= maximumFungibleAmount else {
            throw OpalBase.CashTokens.Error.invalidFungibleAmountString(amountString)
        }
        return amountValue == 0 ? nil : amountValue
    }
}

private extension _OpalBase.CashTokens.NFT {
    init(swiftFulcrumNFT: SwiftFulcrum.CashTokens.TokenData.NFT) throws {
        let capability = OpalBase.CashTokens.NFT.Capability(swiftFulcrumCapability: swiftFulcrumNFT.capability)
        guard !swiftFulcrumNFT.commitment.hasPrefix("0x"),
              !swiftFulcrumNFT.commitment.hasPrefix("0X")
        else {
            throw OpalBase.CashTokens.Error.invalidHexadecimalString
        }
        let commitment: Data
        do {
            commitment = try Data(hexadecimalString: swiftFulcrumNFT.commitment)
        } catch {
            throw OpalBase.CashTokens.Error.invalidHexadecimalString
        }
        try self.init(capability: capability, commitment: commitment)
    }
}

private extension _OpalBase.CashTokens.NFT.Capability {
    init(swiftFulcrumCapability: SwiftFulcrum.CashTokens.TokenData.NFT.Capability) {
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
