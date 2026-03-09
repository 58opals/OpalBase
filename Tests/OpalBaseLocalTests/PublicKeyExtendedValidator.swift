// PublicKeyExtendedValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.PublicKey.Extended", .tags(.unit, .key))
struct PublicKeyExtendedValidator {
    @Test("serialize encodes the mainnet version prefix")
    func serializeEncodesMainnetVersionPrefix() throws {
        let mnemonic = try OpalBase.Mnemonic(words: [
            "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
        ])
        let rootKey = try OpalBase.PrivateKey.Extended.Root(seed: mnemonic.seed)
        let extendedPrivateKey = OpalBase.PrivateKey.Extended(rootKey: rootKey)
        let extendedPublicKey = try OpalBase.PublicKey.Extended(extendedPrivateKey: extendedPrivateKey)
        
        let serialized = extendedPublicKey.serialize()
        let prefix = serialized.prefix(4)
        
        #expect(prefix == Data([0x04, 0x88, 0xB2, 0x1E]))
    }
    
    @Test("init rejects invalid format and length")
    func initRejectsInvalidFormatAndLength() throws {
        #expect(throws: OpalBase.PublicKey.Error.invalidFormat) {
            _ = try OpalBase.PublicKey.Extended(xpub: "xpub0invalidformat")
        }
        
        let invalidLengthData = Data(repeating: 0x01, count: 10)
        let invalidLengthString = Base58.encode(invalidLengthData)
        
        #expect(throws: OpalBase.PublicKey.Error.invalidLength) {
            _ = try OpalBase.PublicKey.Extended(xpub: invalidLengthString)
        }
    }
}

