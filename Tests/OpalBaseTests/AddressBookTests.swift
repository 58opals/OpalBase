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
        self.addressBook = try await .init(rootExtendedKey: rootExtendedKey,
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
        #expect(await addressBook.gapLimit == 20, "Gap limit should be set correctly.")
        #expect(await addressBook.receivingEntries.count == 20, "There should be 20 receiving entries initialized.")
        #expect(await addressBook.changeEntries.count == 20, "There should be 20 change entries initialized.")
    }
    
    @Test mutating func testGenerateNewAddresses() async throws {
        let previousCount = await addressBook.receivingEntries.count
        try await addressBook.generateEntries(for: .receiving, numberOfNewEntries: 1, isUsed: false)
        
        #expect(await addressBook.receivingEntries.count == previousCount + 1, "A new address should be generated.")
    }
    
    @Test mutating func testGetBalanceFromCache() async throws {
        var entry = await addressBook.receivingEntries[0]
        entry.cache = Address.Book.Entry.Cache(balance: try Satoshi(500_000))
        
        try await addressBook.updateCache(for: entry.address, with: try Satoshi(500_000))
        
        let cachedBalance = try await addressBook.getBalanceFromCache(address: entry.address)
        
        #expect(cachedBalance?.uint64 == 500_000, "Balance should be 500,000 satoshis.")
    }
    
    @Test mutating func testGetBalanceFromBlockchain() async throws {
        let entry = await addressBook.receivingEntries[0]
        
        let balance = try await addressBook.getBalanceFromBlockchain(address: entry.address, fulcrum: fulcrum)
        print(balance)
        
        #expect(balance != nil, "Balance should be fetched from the blockchain.")
    }
    
    @Test mutating func testCacheUpdate() async throws {
        var entry = await addressBook.receivingEntries[0]
        entry.cache = Address.Book.Entry.Cache(balance: try Satoshi(100_000), lastUpdated: Date().addingTimeInterval(-600)) // 10 mins ago
        
        #expect(!entry.cache.isValid, "Cache should be invalid after 10 minutes.")
        
        try await addressBook.updateCache(for: entry.address, with: try Satoshi(200_000))
        
        let updatedBalance = try await addressBook.getBalanceFromCache(address: entry.address)
        
        #expect(updatedBalance?.uint64 == 200_000, "Updated cache balance should be 200,000 satoshis.")
    }
    
    @Test mutating func testRefreshUTXOSet() async throws {
        try await addressBook.refreshUTXOSet(fulcrum: fulcrum)
        
        #expect(await addressBook.utxos.count >= 0, "UTXOs should be refreshed and updated.")
    }
    
    @Test func testFindEntryForAddress() async throws {
        let address = await addressBook.receivingEntries[0].address
        let entry = await addressBook.findEntry(for: address)
        
        #expect(entry != nil, "The entry for the given address should be found.")
        #expect(entry?.address.string == address.string, "The addresses should match.")
    }
    
    @Test mutating func testMarkAddressAsUsed() async throws {
        let address = await addressBook.receivingEntries[0].address
        try await addressBook.mark(address: address, isUsed: true)
        
        #expect(await addressBook.receivingEntries[0].isUsed, "The address should be marked as used.")
    }
    
    @Test mutating func testGenerateChangeAddresses() async throws {
        let previousCount = await addressBook.changeEntries.count
        try await addressBook.generateEntries(for: .change, numberOfNewEntries: 5, isUsed: false)
        
        #expect(await addressBook.changeEntries.count == previousCount + 5, "Five new change addresses should be generated.")
    }
    
    @Test mutating func testMarkNonExistentAddressAsUsed() async throws {
        let fakeAddress = try Address(script: .p2pkh(hash: .init(publicKey: try .init(compressedData: .init(repeating: 0x02, count: 33)))))
        
        do {
            try await addressBook.mark(address: fakeAddress, isUsed: true)
            #expect(Bool(false), "Marking a non-existent address should throw an error.")
        } catch Address.Book.Error.addressNotFound {
            #expect(true, "Marking a non-existent address should throw Address.Book.Error.addressNotFound.")
        } catch {
            #expect(Bool(false), "Unexpected error type when marking non-existent address.")
        }
    }
    
    @Test mutating func testGenerateAddressBeyondMaximumIndex() async throws {
        let usage: DerivationPath.Usage = .receiving
        let index: UInt32 = UInt32.max
        
        do {
            _ = try await addressBook.generateAddress(at: index, for: usage)
            #expect(true, "Generating an address at UInt32.max should succeed if possible.")
        } catch {
            #expect(Bool(false), "Generating an address at UInt32.max should not throw an error unless index is out of bounds.")
        }
    }
    
    @Test mutating func testUTXOAdditionAndRemoval() async throws {
        // Create a dummy unspent transaction output (UTXO)
        let dummyOutput = Transaction.Output(value: 100_000, lockingScript: Script.p2pkh(hash: .init(publicKey: try .init(compressedData: .init(repeating: 0x02, count: 33)))).data)
        let dummyUTXO = Transaction.Output.Unspent(output: dummyOutput,
                                                   previousTransactionHash: Transaction.Hash(naturalOrder: Data(repeating: 0x00, count: 32)),
                                                   previousTransactionOutputIndex: 0)
        
        // Add the UTXO
        await addressBook.addUTXO(dummyUTXO)
        #expect(await addressBook.utxos.contains(dummyUTXO), "UTXO should be added to the address book.")
        
        // Remove the UTXO
        await addressBook.removeUTXO(dummyUTXO)
        #expect(await !addressBook.utxos.contains(dummyUTXO), "UTXO should be removed from the address book.")
    }
    
    @Test mutating func testCacheInvalidationOnManualUpdate() async throws {
        let address = await addressBook.receivingEntries[1].address
        try await addressBook.updateCache(for: address, with: try Satoshi(300_000))
        
        // Ensure cache is valid immediately after update
        let balance1 = try await addressBook.getBalanceFromCache(address: address)
        #expect(balance1?.uint64 == 300_000, "Initial cached balance should be 300,000 satoshis.")
        
        // Manually update the cache with a new balance
        try await addressBook.updateCache(for: address, with: try Satoshi(400_000))
        
        let balance2 = try await addressBook.getBalanceFromCache(address: address)
        #expect(balance2?.uint64 == 400_000, "Updated cached balance should be 400,000 satoshis.")
    }
    
    @Test mutating func testFindEntryForNonExistentAddress() async throws {
        let fakeAddress = try Address(script: .p2pkh(hash: .init(publicKey: try .init(compressedData: .init(repeating: 0x02, count: 33)))))
        let entry = await addressBook.findEntry(for: fakeAddress)
        
        #expect(entry == nil, "Finding a non-existent address should return nil.")
    }
    
    @Test mutating func testMaxGapLimitEnforcement() async throws {
        let usage: DerivationPath.Usage = .receiving
        let initialGapLimit = await addressBook.gapLimit
        let usedAddressesCount = initialGapLimit
        
        for index in 0..<usedAddressesCount {
            let address = await addressBook.receivingEntries[index].address
            try await addressBook.mark(address: address, isUsed: true)
        }
        
        #expect(await addressBook.receivingEntries.count == 20 + 20, "Gap limit enforcement should generate additional entries to maintain the gap.")
    }
}
