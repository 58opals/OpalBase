// AddressBookUnspentTransactionOutputSelectionValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Address BookActor UTXO Selection", .tags(.unit, .address))
struct AddressBookUnspentTransactionOutputSelectionValidator {
    @Test("BCH selection excludes token UTXOs by default")
    func selectUnspentTransactionOutputsExcludesTokenOutputsForBitcoinCashPayments() async throws {
        let book = try await makeAddressBook()
        let tokenData = try makeTokenData()
        let lockingScript = Data([0x51])
        let transactionHash = OpalBase.Transaction.HashModel(naturalOrder: Data(repeating: 0x11, count: 32))
        let bchOnlyUTXO = OpalBase.Transaction.OutputModel.Unspent(value: 5_000,
                                                     lockingScript: lockingScript,
                                                     tokenData: nil,
                                                     previousTransactionHash: transactionHash,
                                                     previousTransactionOutputIndex: 0)
        let tokenUTXO = OpalBase.Transaction.OutputModel.Unspent(value: 9_000,
                                                   lockingScript: lockingScript,
                                                   tokenData: tokenData,
                                                   previousTransactionHash: transactionHash,
                                                   previousTransactionOutputIndex: 1)
        
        await book.addUTXOs([bchOnlyUTXO, tokenUTXO])
        
        let selection = try await book.selectUTXOs(targetAmount: try OpalBase.Satoshi(900),
                                                   feePolicy: .init(),
                                                   override: .init(explicitFeeRate: 0))
        
        #expect(selection == [bchOnlyUTXO])
        #expect(selection.allSatisfy { $0.tokenData == nil })
    }
    
    @Test("BCH selection fails when only token UTXOs are available")
    func selectUnspentTransactionOutputsThrowWhenOnlyTokenOutputsAreSpendable() async throws {
        let book = try await makeAddressBook()
        let tokenData = try makeTokenData()
        let lockingScript = Data([0x51])
        let transactionHash = OpalBase.Transaction.HashModel(naturalOrder: Data(repeating: 0x22, count: 32))
        let tokenUTXO = OpalBase.Transaction.OutputModel.Unspent(value: 2_000,
                                                   lockingScript: lockingScript,
                                                   tokenData: tokenData,
                                                   previousTransactionHash: transactionHash,
                                                   previousTransactionOutputIndex: 0)
        
        await book.addUTXOs([tokenUTXO])
        
        await #expect(throws: OpalBase.Address.Book.Error.insufficientFunds) {
            _ = try await book.selectUTXOs(targetAmount: try OpalBase.Satoshi(1_000),
                                           feePolicy: .init(),
                                           override: .init(explicitFeeRate: 0))
        }
    }
}

private extension AddressBookUnspentTransactionOutputSelectionValidator {
    func makeAddressBook() async throws -> OpalBase.Address.Book {
        let mnemonic = try OpalBase.Mnemonic(words: [
            "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
            "abandon", "abandon", "abandon", "abandon", "abandon", "about"
        ])
        let rootExtendedPrivateKey = OpalBase.PrivateKey.ExtendedModel(rootKey: try .init(seed: mnemonic.seed))
        return try await OpalBase.Address.Book(rootExtendedPrivateKey: rootExtendedPrivateKey,
                                      purpose: .bip44,
                                      coinType: .bitcoinCash,
                                      account: .init(rawIndexInteger: 0),
                                      gapLimit: 2)
    }
    
    func makeTokenData() throws -> OpalBase.CashTokens.TokenData {
        let fixture = try #require(TokenPrefixTestData.validVectors.first)
        return try makeTokenData(from: fixture.data)
    }
    
    func makeTokenData(from fixture: TokenPrefixTokenData) throws -> OpalBase.CashTokens.TokenData {
        let category = try OpalBase.CashTokens.CategoryIDModel(hexFromRPC: fixture.category)
        let amount = try parseAmount(from: fixture.amount)
        let nonFungibleToken = try fixture.nonFungibleToken.map { try makeNonFungibleToken(from: $0) }
        return OpalBase.CashTokens.TokenData(category: category, amount: amount, nft: nonFungibleToken)
    }
    
    func parseAmount(from amountString: String?) throws -> UInt64? {
        guard let amountString else {
            return nil
        }
        guard let amountValue = UInt64(amountString) else {
            throw OpalBase.CashTokens.Error.invalidFungibleAmountString(amountString)
        }
        return amountValue == 0 ? nil : amountValue
    }
    
    func makeNonFungibleToken(from fixture: TokenPrefixNonFungibleTokenData) throws -> OpalBase.CashTokens.NFTModel {
        let capability = try makeNonFungibleCapability(from: fixture.capability)
        let commitment = try Data(hexadecimalString: fixture.commitment)
        return try OpalBase.CashTokens.NFTModel(capability: capability, commitment: commitment)
    }
    
    func makeNonFungibleCapability(from capabilityString: String) throws -> OpalBase.CashTokens.NFTModel.Capability {
        switch capabilityString {
        case "none":
            return .none
        case "mutable":
            return .mutable
        case "minting":
            return .minting
        default:
            throw OpalBase.CashTokens.Error.invalidTokenPrefixCapability
        }
    }
}
