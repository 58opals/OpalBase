// TransactionOutputOrderValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Transaction output ordering", .tags(.unit, .transaction))
struct TransactionOutputOrderValidator {
    @Test("applyBIP69Ordering sorts token prefix fields", arguments: TokenPrefixOrderingCase.allCases)
    fileprivate func applyBIP69OrderingSortsTokenPrefixFields(_ testCase: TokenPrefixOrderingCase) throws {
        let outputPair = try testCase.makeOutputPair(makeCategory: makeCategory)
        
        let orderedOutputs = try OpalBase.Transaction.Output.applyBIP69Ordering(outputPair.unordered)
        
        #expect(orderedOutputs == outputPair.expected)
    }
    
    @Test("applyBIP69Ordering rejects invalid token prefix data")
    func applyBIP69OrderingRejectsInvalidTokenPrefixData() throws {
        let category = try makeCategory(using: 0x01)
        let invalidTokenData = OpalBase.CashTokens.TokenData(category: category, amount: nil, nft: nil)
        let invalidOutput = OpalBase.Transaction.Output(
            value: 1_000,
            lockingScript: Data([0x51]),
            tokenData: invalidTokenData
        )

        #expect(throws: OpalBase.CashTokens.Error.invalidTokenPrefix) {
            _ = try OpalBase.Transaction.Output.applyBIP69Ordering([invalidOutput])
        }
    }
    
    private func makeCategory(using byte: UInt8) throws -> OpalBase.CashTokens.CategoryID {
        try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: byte, count: 32))
    }

    enum TokenPrefixOrderingCase: CaseIterable, CustomStringConvertible, Sendable {
        case tokenPresence
        case tokenAmount
        case categoryBeforeNonFungibleTokenData
        case categoryBeforeTokenAmount

        var description: String {
            switch self {
            case .tokenPresence:
                "tokenPresence"
            case .tokenAmount:
                "tokenAmount"
            case .categoryBeforeNonFungibleTokenData:
                "categoryBeforeNonFungibleTokenData"
            case .categoryBeforeTokenAmount:
                "categoryBeforeTokenAmount"
            }
        }

        func makeOutputPair(
            makeCategory: (UInt8) throws -> OpalBase.CashTokens.CategoryID
        ) throws -> (unordered: [OpalBase.Transaction.Output], expected: [OpalBase.Transaction.Output]) {
            let lockingScript = Data([0x51])
            let category = try makeCategory(0x01)

            switch self {
            case .tokenPresence:
                let tokenData = OpalBase.CashTokens.TokenData(category: category, amount: 1, nft: nil)
                let tokenOutput = OpalBase.Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: tokenData)
                let plainOutput = OpalBase.Transaction.Output(value: 1_000, lockingScript: lockingScript)
                return ([tokenOutput, plainOutput], [plainOutput, tokenOutput])
            case .tokenAmount:
                let smallerAmount = OpalBase.CashTokens.TokenData(category: category, amount: 1, nft: nil)
                let largerAmount = OpalBase.CashTokens.TokenData(category: category, amount: 2, nft: nil)
                let smallerOutput = OpalBase.Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: smallerAmount)
                let largerOutput = OpalBase.Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: largerAmount)
                return ([largerOutput, smallerOutput], [smallerOutput, largerOutput])
            case .categoryBeforeNonFungibleTokenData:
                let smallerCategory = try makeCategory(0x01)
                let largerCategory = try makeCategory(0x02)
                let noneCapability = try OpalBase.CashTokens.NFT(capability: .none, commitment: Data())
                let mintingCapability = try OpalBase.CashTokens.NFT(capability: .minting, commitment: Data())
                let smallerToken = OpalBase.CashTokens.TokenData(category: smallerCategory, amount: 1, nft: mintingCapability)
                let largerToken = OpalBase.CashTokens.TokenData(category: largerCategory, amount: 1, nft: noneCapability)
                let smallerOutput = OpalBase.Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: smallerToken)
                let largerOutput = OpalBase.Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: largerToken)
                return ([largerOutput, smallerOutput], [smallerOutput, largerOutput])
            case .categoryBeforeTokenAmount:
                let smallerCategory = try makeCategory(0x01)
                let largerCategory = try makeCategory(0x02)
                let baseToken = try OpalBase.CashTokens.NFT(capability: .none, commitment: Data())
                let smallerToken = OpalBase.CashTokens.TokenData(category: smallerCategory, amount: 2, nft: baseToken)
                let largerToken = OpalBase.CashTokens.TokenData(category: largerCategory, amount: 1, nft: baseToken)
                let smallerOutput = OpalBase.Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: smallerToken)
                let largerOutput = OpalBase.Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: largerToken)
                return ([largerOutput, smallerOutput], [smallerOutput, largerOutput])
            }
        }
    }
}
