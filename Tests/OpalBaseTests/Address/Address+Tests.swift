import Testing
@testable import OpalBase

@Suite("CashAddr", .tags(.unit, .address))
struct AddressTests {
    @Test("cash address decodes to P2PKH script")
    func testDecodeCashAddressToP2PKHScript() throws {
        let cashaddr = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
        let address = try Address(cashaddr)
        #expect(address.string == cashaddr)
        
        switch address.lockingScript {
        case .p2pkh_OPCHECKSIG(let hash):
            #expect(hash.data.count == 20)
        default:
            #expect(Bool(false), "Expected P2PKH locking script")
        }
    }
    
    @Test("cash address accepts uppercase payload")
    func testDecodeCashAddressWithUppercasePayload() throws {
        let cashaddr = "bitcoincash:QPM2QSZNHKS23Z7629MMS6S4CWEF74VCWVY22GDX6A"
        let address = try Address(cashaddr)
        #expect(address.string == cashaddr)
        
        switch address.lockingScript {
        case .p2pkh_OPCHECKSIG(let hash):
            #expect(hash.data.count == 20)
        default:
            #expect(Bool(false), "Expected P2PKH locking script")
        }
    }
    
    @Test("cash address accepts uppercase prefix")
    func testDecodeCashAddressWithUppercasePrefix() throws {
        let cashaddr = "BITCOINCASH:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
        let address = try Address(cashaddr)
        #expect(address.string == cashaddr)
        
        switch address.lockingScript {
        case .p2pkh_OPCHECKSIG(let hash):
            #expect(hash.data.count == 20)
        default:
            #expect(Bool(false), "Expected P2PKH locking script")
        }
    }
    
    @Test("filter removes invalid characters")
    func testFilterRemovesInvalidCharacters() {
        let noisy = "BITCOINCASH:QPM2-QSZN HK S23Z7629MMS6S4CWEF74VCWVY22GDX6A"
        let filtered = Address.filterBase32(from: noisy)
        #expect(filtered == "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
    }
    
    @Test("filter lowercases uppercase characters")
    func testFilterLowercasesUppercaseCharacters1() {
        let noisy = "BITCOINCASH:QPY0"
        let filtered = Address.filterBase32(from: noisy)
        #expect(filtered == "qpy0")
    }
    
    @Test("filter normalizes uppercase Base32 characters", .tags(.unit))
    func testFilterBase32LowercasesUppercaseCharacters() {
        let uppercaseCandidate = "BITCOINCASH:QPZA"
        let filtered = Address.filterBase32(from: uppercaseCandidate)
        #expect(filtered == "qpza")
    }
    
    @Test("filter normalizes uppercase characters to lowercase")
    func testFilterNormalizesUppercaseCharactersToLowercase() {
        let uppercasePayload = "BITCOINCASH:QPM2QSZNHKS23Z7629MMS6S4CWEF74VCWVY22GDX6A"
        let filtered = Address.filterBase32(from: uppercasePayload)
        #expect(filtered == "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
    }
    
    @Test("filter lowercases uppercase characters")
    func testFilterLowercasesUppercaseCharacters2() {
        let uppercase = "BITCOINCASH:QPM2QSZNHKS23Z7629MMS6S4CWEF74VCWVY22GDX6A"
        let filtered = Address.filterBase32(from: uppercase)
        #expect(filtered == "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
    }
    
    @Test("invalid checksum is rejected")
    func testRejectInvalidChecksum() {
        let invalid = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6z"
        #expect(throws: Address.Error.invalidChecksum) {
            _ = try Address(invalid)
        }
    }
    
    @Test("address book only replenishes the gap deficit")
    func testAddressBookMaintainsGapLimit() async throws {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let rootExtendedPrivateKey = PrivateKey.Extended(rootKey: try .init(seed: mnemonic.seed))
        let account = try DerivationPath.Account(rawIndexInteger: 0)
        let gapLimit = 5
        let book = try await Address.Book(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: account,
            gapLimit: gapLimit
        )
        
        let initialTotal = await book.countEntries(for: .receiving)
        #expect(initialTotal == gapLimit)
        
        let entries = await book.listEntries(for: .receiving)
        let firstEntry = try #require(entries.first)
        try await book.mark(address: firstEntry.address, isUsed: true)
        
        let updatedTotal = await book.countEntries(for: .receiving)
        let updatedUnused = await book.countUnusedEntries(for: .receiving)
        
        #expect(updatedTotal == initialTotal + 1)
        #expect(updatedUnused == gapLimit)
    }
}
