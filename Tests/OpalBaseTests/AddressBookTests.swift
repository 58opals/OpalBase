import Testing
import Foundation
import SwiftFulcrum
@testable import OpalBase

@Suite("Address Book Tests")
struct AddressBookTests {
    let fulcrum: Fulcrum
    var addressBook: Address.Book
    let rootExtendedKey: PrivateKey.Extended
    let purpose: DerivationPath.Purpose = .bip44
    let coinType: DerivationPath.CoinType = .bitcoinCash
    let account = DerivationPath.Account(unhardenedIndex: 0)
    
    init() async throws {
        self.fulcrum = try .init()
        self.rootExtendedKey = .init(rootKey: try .init(seed: .init([0x00])))
        self.addressBook = try .init(rootExtendedKey: rootExtendedKey,
                                     purpose: purpose,
                                     coinType: coinType,
                                     account: account,
                                     gapLimit: 20)
        
        try await self.fulcrum.start()
    }
}

extension AddressBookTests {
    @Test func testAddressBookInitialization() async throws {
        #expect(addressBook != nil, "Address.Book should be initialized.")
        #expect(addressBook.gapLimit == 20, "Gap limit should be set correctly.")
        #expect(addressBook.receivingEntries.count == 20, "There should be 20 receiving entries initialized.")
        #expect(addressBook.changeEntries.count == 20, "There should be 20 change entries initialized.")
    }
    
    @Test mutating func testGenerateNewAddresses() async throws {
        let previousCount = addressBook.receivingEntries.count
        try addressBook.generateEntries(for: .receiving, numberOfNewEntries: 1, isUsed: false)
        
        #expect(addressBook.receivingEntries.count == previousCount + 1, "A new address should be generated.")
    }
    
    @Test mutating func testGetBalanceFromCache() async throws {
        var entry = addressBook.receivingEntries[0]
        entry.cache = Address.Book.Entry.Cache(balance: try Satoshi(500_000))
        
        try addressBook.updateCache(for: entry.address, with: try Satoshi(500_000))
        
        let cachedBalance = try addressBook.getBalanceFromCache(address: entry.address)
        
        #expect(cachedBalance?.uint64 == 500_000, "Balance should be 500,000 satoshis.")
    }
    
    @Test mutating func testGetBalanceFromBlockchain() async throws {
        let entry = addressBook.receivingEntries[0]
        
        let balance = try await addressBook.getBalanceFromBlockchain(address: entry.address, fulcrum: fulcrum)
        print(balance)
        
        #expect(balance != nil, "Balance should be fetched from the blockchain.")
    }
    
    @Test mutating func testCacheUpdate() async throws {
        var entry = addressBook.receivingEntries[0]
        entry.cache = Address.Book.Entry.Cache(balance: try Satoshi(100_000), lastUpdated: Date().addingTimeInterval(-600)) // 10 mins ago
        
        #expect(!entry.cache.isValid, "Cache should be invalid after 10 minutes.")
        
        try addressBook.updateCache(for: entry.address, with: try Satoshi(200_000))
        
        let updatedBalance = try addressBook.getBalanceFromCache(address: entry.address)
        
        #expect(updatedBalance?.uint64 == 200_000, "Updated cache balance should be 200,000 satoshis.")
    }
    
    @Test mutating func testRefreshUTXOSet() async throws {
        try await addressBook.refreshUTXOSet(fulcrum: fulcrum)
        
        #expect(addressBook.utxos.count >= 0, "UTXOs should be refreshed and updated.")
    }
    
    @Test func testFindEntryForAddress() async throws {
        let address = addressBook.receivingEntries[0].address
        let entry = addressBook.findEntry(for: address)
        
        #expect(entry != nil, "The entry for the given address should be found.")
        #expect(entry?.address.string == address.string, "The addresses should match.")
    }
    
    @Test mutating func testMarkAddressAsUsed() async throws {
        let address = addressBook.receivingEntries[0].address
        try addressBook.mark(address: address, isUsed: true)
        
        #expect(addressBook.receivingEntries[0].isUsed, "The address should be marked as used.")
    }
}
