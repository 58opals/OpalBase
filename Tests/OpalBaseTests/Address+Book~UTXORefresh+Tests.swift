import Foundation
import Testing
@testable import OpalBase

// MARK: - Unit
@Suite("Address Book UTXO Refresh", .tags(.unit, .address, .cashTokens))
struct AddressBookUTXORefreshTests {
    @Test("refresh stores token data from unspent outputs (explicit usage)")
    func testRefreshStoresTokenDataFromUnspentOutputs() async throws {
        let book = try await AddressBookCashTokensTestSupport.makeAddressBook()
        let entry = try await book.selectNextEntry(for: .receiving)
        
        let tokenData = try AddressBookCashTokensTestSupport.makeTokenData()
        let utxo = Transaction.Output.Unspent(
            value: 12_345,
            lockingScript: entry.address.lockingScript.data,
            tokenData: tokenData,
            previousTransactionHash: Transaction.Hash(
                naturalOrder: Data(repeating: 0x11, count: 32)
            ),
            previousTransactionOutputIndex: 1
        )
        
        let reader = AddressReaderStub(unspentByAddress: [entry.address.string: [utxo]])
        
        let refresh = try await book.refreshUTXOSet(using: reader, usage: .receiving)
        
        let refreshedOutputs = try #require(refresh.utxosByAddress[entry.address])
        #expect(refreshedOutputs.count == 1)
        #expect(refreshedOutputs.first?.tokenData == tokenData)
        
        let storedOutputs = await book.listUTXOs(for: entry.address)
        #expect(storedOutputs.count == 1)
        #expect(storedOutputs.first?.tokenData == tokenData)
    }
    
    @Test("refresh stores token data from unspent outputs (all usages)")
    func testRefreshStoresTokenDataFromUnspentOutputsWhenUsageIsNil() async throws {
        let book = try await AddressBookCashTokensTestSupport.makeAddressBook()
        let entry = try await book.selectNextEntry(for: .receiving)
        
        let tokenData = try AddressBookCashTokensTestSupport.makeTokenData()
        let utxo = Transaction.Output.Unspent(
            value: 7_000,
            lockingScript: entry.address.lockingScript.data,
            tokenData: tokenData,
            previousTransactionHash: Transaction.Hash(
                naturalOrder: Data(repeating: 0x33, count: 32)
            ),
            previousTransactionOutputIndex: 0
        )
        
        let reader = AddressReaderStub(unspentByAddress: [entry.address.string: [utxo]])
        
        let refresh = try await book.refreshUTXOSet(using: reader)
        
        let refreshedOutputs = try #require(refresh.utxosByAddress[entry.address])
        #expect(refreshedOutputs.count == 1)
        #expect(refreshedOutputs.first?.tokenData == tokenData)
        
        let storedOutputs = await book.listUTXOs(for: entry.address)
        #expect(storedOutputs.count == 1)
        #expect(storedOutputs.first?.tokenData == tokenData)
    }
}

// MARK: - Network
@Suite("Address Book UTXO Refresh (Network)", .tags(.network, .cashTokens))
struct AddressBookUTXORefreshNetworkTests {
    private static let primaryServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let backupServerAddress = URL(string: "wss://bch.loping.net:50002")!
    private static let tokenCashAddress = "bitcoincash:qqe68ymghsw9derq3v2rgu2jc8a23ddv25t83hevfk"
    
    @Test("listunspent token data reaches the UTXO store", .timeLimit(.minutes(1)))
    func testNetworkTokenUTXOIngestion() async throws {
        let book = try await AddressBookCashTokensTestSupport.makeAddressBook()
        let address = try Address(Self.tokenCashAddress)
        
        let configuration = Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let reader = Network.FulcrumAddressReader(client: client)
            
            let tokenOutputs = try await reader.fetchUnspentOutputs(
                for: Self.tokenCashAddress,
                tokenFilter: .only
            )
            
            #expect(!tokenOutputs.isEmpty)
            #expect(tokenOutputs.allSatisfy { $0.tokenData != nil })
            
            _ = try await book.replaceUTXOs(
                for: address,
                with: tokenOutputs,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000)
            )
            
            let storedOutputs = await book.listUTXOs(for: address)
            #expect(storedOutputs.count == tokenOutputs.count)
            #expect(storedOutputs.allSatisfy { $0.tokenData != nil })
        }
    }
}

// MARK: - Test Support
private struct AddressReaderStub: Network.AddressReadable {
    let unspentByAddress: [String: [Transaction.Output.Unspent]]
    
    func fetchBalance(for address: String, tokenFilter: Network.TokenFilter) async throws -> Network.AddressBalance {
        Network.AddressBalance(confirmed: 0, unconfirmed: 0)
    }
    
    func fetchUnspentOutputs(for address: String, tokenFilter: Network.TokenFilter) async throws -> [Transaction.Output.Unspent] {
        unspentByAddress[address, default: []]
    }
    
    func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [Network.TransactionHistoryEntry] {
        []
    }
    
    func fetchFirstUse(for address: String) async throws -> Network.AddressFirstUse? {
        nil
    }
    
    func fetchMempoolTransactions(for address: String) async throws -> [Network.TransactionHistoryEntry] {
        []
    }
    
    func fetchScriptHash(for address: String) async throws -> String {
        ""
    }
    
    func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<Network.AddressSubscriptionUpdate, any Swift.Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private enum AddressBookCashTokensTestSupport {
    static func makeAddressBook() async throws -> Address.Book {
        let mnemonic = try Mnemonic(words: [
            "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
            "abandon", "abandon", "abandon", "abandon", "abandon", "about",
        ])
        
        let rootExtendedPrivateKey = PrivateKey.Extended(rootKey: try .init(seed: mnemonic.seed))
        
        return try await Address.Book(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: .init(rawIndexInteger: 0),
            gapLimit: 2
        )
    }
    
    static func makeTokenData() throws -> CashTokens.TokenData {
        let fixture = try #require(TokenPrefixFixtureStore.validVectors.first)
        return try makeTokenData(from: fixture.data)
    }
    
    static func makeTokenData(from fixture: TokenPrefixTokenDataFixture) throws -> CashTokens.TokenData {
        let categoryData = try Data(hexadecimalString: fixture.category)
        let category = try CashTokens.CategoryID(transactionOrderData: categoryData)
        
        let amount = try parseAmount(from: fixture.amount)
        let nonFungibleToken = try fixture.nonFungibleToken.map { try makeNonFungibleToken(from: $0) }
        
        return CashTokens.TokenData(category: category, amount: amount, nft: nonFungibleToken)
    }
    
    static func parseAmount(from amountString: String?) throws -> UInt64? {
        guard let amountString else { return nil }
        guard let amountValue = UInt64(amountString) else {
            throw CashTokens.Error.invalidFungibleAmountString(amountString)
        }
        return amountValue == 0 ? nil : amountValue
    }
    
    static func makeNonFungibleToken(from fixture: TokenPrefixNonFungibleTokenFixture) throws -> CashTokens.NFT {
        let capability = try makeNonFungibleCapability(from: fixture.capability)
        let commitment = try Data(hexadecimalString: fixture.commitment)
        return try CashTokens.NFT(capability: capability, commitment: commitment)
    }
    
    static func makeNonFungibleCapability(from capabilityString: String) throws -> CashTokens.NFT.Capability {
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
