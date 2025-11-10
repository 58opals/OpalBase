import Foundation
import Testing
@testable import OpalBase

@Suite("PublicKey.Extended", .tags(.unit, .key))
struct PublicKeyExtendedTests {
    @Test("serialize encodes the mainnet version prefix")
    func testSerializeEncodesMainnetVersionPrefix() throws {
        let mnemonic = try Mnemonic(words: [
            "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
        ])
        let rootKey = try PrivateKey.Extended.Root(seed: mnemonic.seed)
        let extendedPrivateKey = PrivateKey.Extended(rootKey: rootKey)
        let extendedPublicKey = try PublicKey.Extended(extendedPrivateKey: extendedPrivateKey)
        
        let serialized = extendedPublicKey.serialize()
        let prefix = serialized.prefix(4)
        
        #expect(prefix == Data([0x04, 0x88, 0xB2, 0x1E]))
    }
}
