import Foundation
import Testing
@testable import OpalBase

@Suite("PrivateKey.Extended", .tags(.unit, .key))
struct PrivateKeyExtendedTests {
    @Test("serialize encodes the mainnet version prefix")
    func testSerializeEncodesMainnetVersionPrefix() throws {
        let mnemonic = try Mnemonic(words: [
            "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
        ])
        let rootKey = try PrivateKey.Extended.Root(seed: mnemonic.seed)
        let extendedPrivateKey = PrivateKey.Extended(rootKey: rootKey)
        
        let serialized = extendedPrivateKey.serialize()
        let prefix = serialized.prefix(4)
        
        #expect(prefix == Data([0x04, 0x88, 0xAD, 0xE4]))
    }
    
    @Test("init rejects invalid format and length")
    func testInitRejectsInvalidFormatAndLength() throws {
        #expect(throws: PrivateKey.Error.invalidFormat) {
            _ = try PrivateKey.Extended(xprv: "xprv0invalidformat")
        }
        
        let invalidLengthData = Data(repeating: 0x01, count: 10)
        let invalidLengthString = Base58.encode(invalidLengthData)
        
        #expect(throws: PrivateKey.Error.invalidLength) {
            _ = try PrivateKey.Extended(xprv: invalidLengthString)
        }
    }
}
