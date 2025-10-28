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
    
    @Test("filter removes invalid characters")
    func testFilterRemovesInvalidCharacters() {
        let noisy = "BITCOINCASH:QPM2-QSZN HK S23Z7629MMS6S4CWEF74VCWVY22GDX6A"
        let filtered = Address.filterBase32(from: noisy)
        #expect(filtered == "QPM2QSZNHKS23Z7629MMS6S4CWEF74VCWVY22GDX6A")
    }
    
    @Test("invalid checksum is rejected")
    func testRejectInvalidChecksum() {
        let invalid = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6z"
        #expect(throws: Address.Error.invalidChecksum) {
            _ = try Address(invalid)
        }
    }
}
