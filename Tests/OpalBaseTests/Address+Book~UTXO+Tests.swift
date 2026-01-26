import Foundation
import Testing
@testable import OpalBase

@Suite("Address Book UTXO Selection", .tags(.unit, .address))
struct AddressBookUTXOSelectionTests {
    @Test("BCH selection excludes token UTXOs by default")
    func testSelectUTXOsExcludesTokenOutputsForBitcoinCashPayments() async throws {
        let book = try await makeAddressBook()
        let tokenData = try makeTokenData()
        let lockingScript = Data([0x51])
        let transactionHash = Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32))
        let bchOnlyUTXO = Transaction.Output.Unspent(value: 5_000,
                                                     lockingScript: lockingScript,
                                                     tokenData: nil,
                                                     previousTransactionHash: transactionHash,
                                                     previousTransactionOutputIndex: 0)
        let tokenUTXO = Transaction.Output.Unspent(value: 9_000,
                                                   lockingScript: lockingScript,
                                                   tokenData: tokenData,
                                                   previousTransactionHash: transactionHash,
                                                   previousTransactionOutputIndex: 1)
        
        await book.addUTXOs([bchOnlyUTXO, tokenUTXO])
        
        let selection = try await book.selectUTXOs(targetAmount: try Satoshi(900),
                                                   feePolicy: .init(),
                                                   override: .init(explicitFeeRate: 0))
        
        #expect(selection == [bchOnlyUTXO])
        #expect(selection.allSatisfy { $0.tokenData == nil })
    }
    
    @Test("BCH selection fails when only token UTXOs are available")
    func testSelectUTXOsThrowsWhenOnlyTokenOutputsAreSpendable() async throws {
        let book = try await makeAddressBook()
        let tokenData = try makeTokenData()
        let lockingScript = Data([0x51])
        let transactionHash = Transaction.Hash(naturalOrder: Data(repeating: 0x22, count: 32))
        let tokenUTXO = Transaction.Output.Unspent(value: 2_000,
                                                   lockingScript: lockingScript,
                                                   tokenData: tokenData,
                                                   previousTransactionHash: transactionHash,
                                                   previousTransactionOutputIndex: 0)
        
        await book.addUTXOs([tokenUTXO])
        
        await #expect(throws: Address.Book.Error.insufficientFunds) {
            _ = try await book.selectUTXOs(targetAmount: try Satoshi(1_000),
                                           feePolicy: .init(),
                                           override: .init(explicitFeeRate: 0))
        }
    }
}

private extension AddressBookUTXOSelectionTests {
    func makeAddressBook() async throws -> Address.Book {
        let mnemonic = try Mnemonic(words: [
            "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
            "abandon", "abandon", "abandon", "abandon", "abandon", "about"
        ])
        let rootExtendedPrivateKey = PrivateKey.Extended(rootKey: try .init(seed: mnemonic.seed))
        return try await Address.Book(rootExtendedPrivateKey: rootExtendedPrivateKey,
                                      purpose: .bip44,
                                      coinType: .bitcoinCash,
                                      account: .init(rawIndexInteger: 0),
                                      gapLimit: 2)
    }
    
    func makeTokenData() throws -> CashTokens.TokenData {
        let fixture = try #require(TokenPrefixFixtureStore.validVectors.first)
        return try makeTokenData(from: fixture.data)
    }
    
    func makeTokenData(from fixture: TokenPrefixTokenDataFixture) throws -> CashTokens.TokenData {
        let categoryData = try Data(hexadecimalString: fixture.category)
        let category = try CashTokens.CategoryID(transactionOrderData: categoryData)
        let amount = try parseAmount(from: fixture.amount)
        let nonFungibleToken = try fixture.nonFungibleToken.map { try makeNonFungibleToken(from: $0) }
        return CashTokens.TokenData(category: category, amount: amount, nft: nonFungibleToken)
    }
    
    func parseAmount(from amountString: String?) throws -> UInt64? {
        guard let amountString else {
            return nil
        }
        guard let amountValue = UInt64(amountString) else {
            throw CashTokens.Error.invalidFungibleAmountString(amountString)
        }
        return amountValue == 0 ? nil : amountValue
    }
    
    func makeNonFungibleToken(from fixture: TokenPrefixNonFungibleTokenFixture) throws -> CashTokens.NFT {
        let capability = try makeNonFungibleCapability(from: fixture.capability)
        let commitment = try Data(hexadecimalString: fixture.commitment)
        return try CashTokens.NFT(capability: capability, commitment: commitment)
    }
    
    func makeNonFungibleCapability(from capabilityString: String) throws -> CashTokens.NFT.Capability {
        switch capabilityString {
        case "none":
            return .none
        case "mutable":
            return .mutable
        case "minting":
            return .minting
        default:
            throw CashTokens.Error.invalidTokenPrefixCapability
        }
    }
}
